// IPMsgX/App/AppState.swift
// Centralized observable app state

import SwiftUI
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "AppState")

@Observable
@MainActor
final class AppState {
    var isAbsent: Bool = false
    /// Index of the active absence definition (-1 when available). Observable so menus update.
    var absenceIndex: Int = -1
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

    /// Tracks received sealed messages whose seal has been opened (by us)
    private var openedSealPacketNos: Set<Int> = []
    /// Tracks sent sealed messages whose seal was opened by the recipient
    var sentSealOpenedPacketNos: Set<Int> = []

    /// Unread, non-absence received messages — drives the badge and "open all unread".
    var unreadMessages: [ReceivedMessage] {
        receivedMessages.filter { !$0.isAbsenceReply && !readPacketNos.contains($0.packetNo) }
    }

    /// Peer name the History window should focus on next appear. Set when a notification is
    /// tapped for a message no longer in memory (e.g. a cold launch) so we can route to History.
    var historyPeerToSelect: String?

    func isSealOpened(packetNo: Int) -> Bool {
        openedSealPacketNos.contains(packetNo)
    }

    func markSealOpened(packetNo: Int) {
        openedSealPacketNos.insert(packetNo)
    }

    private(set) var messageService: MessageService?
    private let networkMonitor = NetworkMonitor()

    /// Manages NSApp activation policy (regular ↔ accessory) based on visible windows.
    /// Owned here so app bootstrap no longer depends on any single window scene.
    let windowObserver = WindowObserver()
    private var didBootstrap = false

    /// One-time app bootstrap. Idempotent — safe to call from multiple scene `.task`
    /// blocks so service startup happens regardless of which window opens first.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await start()
        NotificationService.shared.requestPermission()
        windowObserver.start()
        ClipboardImageManager.cleanupOldFiles()
    }

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
                            // Open a dedicated window for this message (MenuBarView listens
                            // and opens a per-packet window; macOS cascades multiple windows).
                            NotificationCenter.default.post(
                                name: .showReceivedMessage, object: nil,
                                userInfo: ["packetNo": msg.packetNo]
                            )
                        } else {
                            // Non-popup/toast mode — bounce the Dock once to draw attention
                            // (no-op if the app is already frontmost).
                            NSApp.requestUserAttention(.informationalRequest)
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
            absenceIndex = index
            isAbsent = true
        } else {
            settings.absenceIndex = -1
            absenceIndex = -1
            isAbsent = false
        }
        AppIcon.apply(absent: isAbsent)
        NotificationCenter.default.post(name: .absenceChanged, object: nil, userInfo: ["absent": isAbsent])
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
