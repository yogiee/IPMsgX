// IPMsgX/App/AppState.swift
// Centralized observable app state

import SwiftUI
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "AppState")

@Observable
@MainActor
final class AppState {
    var isAbsent: Bool = false
    var networkConnected: Bool = false

    /// Packet numbers of messages the user has actually read (thread view or receive window).
    private var readPacketNos: Set<Int> = []

    /// Computed so it always reflects actual read state — no drift possible.
    var unreadCount: Int {
        receivedMessages.filter { !$0.isAbsenceReply && !readPacketNos.contains($0.packetNo) }.count
    }

    /// Preselected user for the compose window. Always set via requestCompose(user:).
    private(set) var composePreselectedUser: UserInfo? = nil
    /// Bumped on every compose request so SendWindow's onChange fires even for nil → nil.
    private(set) var composeRequestToken: UUID = UUID()

    func requestCompose(user: UserInfo?) {
        composePreselectedUser = user
        composeRequestToken = UUID()
    }

    var onlineUsers: [UserInfo] = []
    var receivedMessages: [ReceivedMessage] = []
    var sentMessages: [SentMessage] = []

    // Pending receive windows — use count for onChange tracking
    var pendingReceiveCount: Int = 0
    private var pendingReceiveQueue: [ReceivedMessage] = []

    /// Tracks messages already shown/queued to prevent duplicate windows
    private var displayedPacketNos: Set<Int> = []
    /// Tracks received sealed messages whose seal has been opened (by us)
    private var openedSealPacketNos: Set<Int> = []
    /// Tracks sent sealed messages whose seal was opened by the recipient
    var sentSealOpenedPacketNos: Set<Int> = []

    func popPendingReceive() -> ReceivedMessage? {
        guard !pendingReceiveQueue.isEmpty else { return nil }
        let msg = pendingReceiveQueue.removeFirst()
        displayedPacketNos.insert(msg.packetNo)
        return msg
    }

    func isSealOpened(packetNo: Int) -> Bool {
        openedSealPacketNos.contains(packetNo)
    }

    func markSealOpened(packetNo: Int) {
        openedSealPacketNos.insert(packetNo)
    }

    private(set) var messageService: MessageService?
    private let networkMonitor = NetworkMonitor()

    private var userSyncTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?

    func start() async {
        guard messageService == nil else { return }  // Already started
        let service = MessageService()
        self.messageService = service

        // Start network monitor
        networkMonitor.start()
        networkTask = Task {
            for await status in networkMonitor.statusStream {
                self.networkConnected = (status == .connected)
            }
        }

        // Pre-fetch stream references BEFORE starting service
        // so we're listening before any events can be produced
        let userService = service.userService
        let userChanges = userService.changes
        let serviceEvents = service.events

        // Set up user sync BEFORE starting service
        userSyncTask = Task {
            logger.info("userSyncTask started, waiting for user changes...")
            for await change in userChanges {
                switch change {
                case .added(let user):
                    if !self.onlineUsers.contains(where: { $0.id == user.id }) {
                        self.onlineUsers.append(user)
                        logger.info("AppState: added \(user.displayName) to onlineUsers (total: \(self.onlineUsers.count))")
                    }
                    PersistenceController.updateContact(user)
                case .updated(let user):
                    if let idx = self.onlineUsers.firstIndex(where: { $0.id == user.id }) {
                        self.onlineUsers[idx] = user
                        logger.debug("AppState: updated \(user.displayName)")
                    }
                    PersistenceController.updateContact(user)
                case .removed(let id):
                    self.onlineUsers.removeAll { $0.id == id }
                    logger.info("AppState: removed user \(id.logOnName)@\(id.ipAddress) (total: \(self.onlineUsers.count))")
                case .cleared:
                    self.onlineUsers.removeAll()
                    logger.info("AppState: cleared all users")
                }
                self.onlineUsers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            logger.warning("userSyncTask ended — stream finished unexpectedly")
        }

        // Set up event sync BEFORE starting service
        eventTask = Task {
            logger.info("eventTask started, waiting for message events...")
            for await event in serviceEvents {
                switch event {
                case .messageReceived(let msg):
                    self.receivedMessages.insert(msg, at: 0)
                    self.postBadgeUpdate()
                    PersistenceController.saveReceivedMessage(msg)
                    if !msg.isAbsenceReply {
                        // Determine if we should open receive window
                        let ns = NotificationService.shared
                        let settings = SettingsService.shared
                        let bannerOnly = ns.hasBannerSupport && (
                            settings.useNotificationBanner
                            || settings.nonPopup
                            || (settings.nonPopupWhenAbsence && self.isAbsent)
                        )
                        if !bannerOnly {
                            // Open receive window directly
                            self.pendingReceiveQueue.append(msg)
                            self.pendingReceiveCount += 1
                        }
                        // Play sound / post banner notification
                        ns.postIncomingMessage(msg)
                    }
                case .sealOpened(let fromUser, let packetNo):
                    logger.info("Seal opened by \(fromUser.displayName)")
                    self.sentSealOpenedPacketNos.insert(packetNo)
                    NotificationService.shared.postSealOpened(by: fromUser, packetNo: packetNo)
                case .messageSent(let packetNo, let toUsers):
                    logger.info("Message \(packetNo) sent to \(toUsers.count) users")
                case .sendRetryFailed(let packetNo, let toUser):
                    logger.warning("Send retry failed for packet \(packetNo) to \(toUser.displayName)")
                }
            }
        }

        // NOW start the service — listeners are already set up
        await service.start()
        logger.info("AppState started, service running")

        // Re-broadcast after a short delay and cull any non-responsive users
        Task {
            try? await Task.sleep(for: .seconds(3))
            await service.refreshUserList()
        }
    }

    func stop() async {
        userSyncTask?.cancel()
        eventTask?.cancel()
        networkTask?.cancel()
        networkMonitor.stop()
        await messageService?.stop()
    }

    func toggleAbsence(index: Int?) {
        let settings = SettingsService.shared
        if let index {
            settings.absenceIndex = index
            isAbsent = true
        } else {
            settings.absenceIndex = -1
            isAbsent = false
        }
        Task {
            await messageService?.broadcastAbsence()
        }
    }

    func sendMessage(to users: [UserInfo], message: String, isSealed: Bool, isLocked: Bool, attachments: [URL] = []) async -> Int? {
        guard let service = messageService else { return nil }
        let packetNo = await service.sendMessage(
            to: users,
            message: message,
            isSealed: isSealed,
            isLocked: isLocked,
            attachments: attachments
        )
        let sent = SentMessage(
            packetNo: packetNo,
            sendDate: Date(),
            message: message,
            toUsers: users,
            isSealed: isSealed,
            isLocked: isLocked,
            attachmentURLs: attachments
        )
        sentMessages.insert(sent, at: 0)
        PersistenceController.saveSentMessage(sent)
        return packetNo
    }

    /// Mark a single message as read (called when its receive window is dismissed).
    func markRead(packetNo: Int) {
        readPacketNos.insert(packetNo)
        postBadgeUpdate()
        NotificationService.shared.removeNotification(for: packetNo)
    }

    /// Mark all messages from a user as read (called when their thread is viewed).
    func markThreadRead(userID: UserIdentifier) {
        let packetNos = receivedMessages
            .filter { $0.fromUser.id == userID && !$0.isAbsenceReply }
            .map { $0.packetNo }
        guard !packetNos.isEmpty else { return }
        for pn in packetNos { readPacketNos.insert(pn) }
        postBadgeUpdate()
        NotificationService.shared.removeNotifications(for: packetNos)
    }

    func markAllRead() {
        for msg in receivedMessages where !msg.isAbsenceReply {
            readPacketNos.insert(msg.packetNo)
        }
        postBadgeUpdate()
        NotificationService.shared.removeAllMessageNotifications()
    }

    /// Queue a specific message for display in the receive window
    func showMessage(packetNo: Int, force: Bool = false) {
        guard force || !displayedPacketNos.contains(packetNo) else { return }
        if let msg = receivedMessages.first(where: { $0.packetNo == packetNo }) {
            displayedPacketNos.insert(packetNo)
            pendingReceiveQueue.append(msg)
            pendingReceiveCount += 1
        }
    }

    /// Queue all unread messages for sequential display, and clear their notification banners.
    func queueAllUnreadForDisplay() {
        let unread = receivedMessages.filter {
            !$0.isAbsenceReply && !readPacketNos.contains($0.packetNo) && !displayedPacketNos.contains($0.packetNo)
        }
        guard !unread.isEmpty else { return }
        NotificationService.shared.removeNotifications(for: unread.map { $0.packetNo })
        for msg in unread {
            displayedPacketNos.insert(msg.packetNo)
        }
        pendingReceiveQueue.append(contentsOf: unread)
        pendingReceiveCount += unread.count
    }

    private func postBadgeUpdate() {
        NotificationCenter.default.post(
            name: .badgeCountChanged, object: nil,
            userInfo: ["count": unreadCount]
        )
    }

    func openSeal(message: ReceivedMessage) async {
        await messageService?.sendOpenSeal(to: message.fromUser, packetNo: message.packetNo)
    }
}
