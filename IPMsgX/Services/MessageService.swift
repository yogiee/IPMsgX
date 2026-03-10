// IPMsgX/Services/MessageService.swift
// Core message orchestration actor
// Ported from MessageCenter.m command handling

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.ipmsgx", category: "MessageService")

// MARK: - Message Events

enum MessageEvent: Sendable {
    case messageReceived(ReceivedMessage)
    case sealOpened(fromUser: UserInfo, packetNo: Int)
    case messageSent(packetNo: Int, toUsers: [UserInfo])
    case sendRetryFailed(packetNo: Int, toUser: UserInfo)
}

actor MessageService {
    private let transport: UDPTransport
    let userService: UserService
    private let settings: SettingsService
    private var cryptoService: CryptoService?
    private let retryService: RetryService
    private let attachmentStore: AttachmentStore
    private let tcpFileServer: TCPFileServer

    private let selfLogOnName: String
    private let selfHostName: String

    private var selfSpec: UInt32
    private var selfFingerprint: String?

    private let selfVersion: String

    private var eventContinuation: AsyncStream<MessageEvent>.Continuation?
    let events: AsyncStream<MessageEvent>

    private var receiveTask: Task<Void, Never>?

    init(
        settings: SettingsService = .shared,
        userService: UserService = UserService()
    ) {
        self.settings = settings
        self.userService = userService
        self.transport = UDPTransport(port: UInt16(settings.portNo))
        self.retryService = RetryService()
        self.attachmentStore = AttachmentStore()
        self.tcpFileServer = TCPFileServer(port: UInt16(settings.portNo))

        self.selfLogOnName = HostInfo.logOnUser
        self.selfHostName = HostInfo.hostName

        // Build self capability spec
        let spec: UInt32 = IPMsgOption.capUtf8Opt.rawValue
            | IPMsgOption.fileAttachOpt.rawValue
            | IPMsgOption.encExtMsgOpt.rawValue
            | IPMsgOption.clipboardOpt.rawValue
        self.selfSpec = spec

        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        self.selfVersion = "IPMsgX \(ver)(\(build)) for macOS"

        var cont: AsyncStream<MessageEvent>.Continuation!
        self.events = AsyncStream { continuation in
            cont = continuation
        }
        self.eventContinuation = cont
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            // Start crypto
            let crypto = CryptoService()
            await crypto.startup()
            self.cryptoService = crypto

            // Compute our RSA2048 fingerprint for the FP: field in BR_ENTRY.
            // Windows IPMSG compares this against its cached fingerprint and sends
            // GETPUBKEY if the fingerprint changed — this is the protocol mechanism
            // for Windows to detect that our public key changed after a restart.
            if let pub2048 = await crypto.publicKey2048,
               let fpData = await crypto.calculateFingerPrint(modulus: pub2048.modulus) {
                selfFingerprint = fpData.map { String(format: "%02X", $0) }.joined()
                NSLog("[CRYPTO] Self RSA2048 fingerprint: %@", selfFingerprint!)
            } else {
                NSLog("[CRYPTO] Warning: could not compute RSA2048 fingerprint — FP: field will be omitted from BR_ENTRY")
            }

            // Update self spec with encryption support (only if enabled in settings)
            let cryptoSupportsEncrypt = await crypto.selfCapability.supportEncryption
            if settings.encryptionEnabled && cryptoSupportsEncrypt {
                selfSpec |= IPMsgOption.encryptOpt.rawValue
            }

            // Start absence spec
            if settings.inAbsence {
                selfSpec |= IPMsgOption.absenceOpt.rawValue
            }

            try await transport.start()
            startReceiving()

            // Start TCP file server for serving attachments to requesters
            let handler = FileTransferHandler(attachmentStore: attachmentStore)
            try await tcpFileServer.start { connection in
                Task {
                    await handler.handleConnection(connection)
                }
            }

            // Broadcast entry
            await broadcastEntry()
            logger.info("MessageService started")
        } catch {
            logger.error("Failed to start MessageService: \(error)")
        }
    }

    func stop() async {
        await broadcastExit()
        receiveTask?.cancel()
        receiveTask = nil
        await tcpFileServer.stop()
        await transport.stop()
        logger.info("MessageService stopped")
    }

    // MARK: - Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.transport.incomingMessages
            for await (data, endpoint) in stream {
                guard !Task.isCancelled else { break }
                await self.processReceived(data: data, from: endpoint)
            }
        }
    }

    private func processReceived(data: Data, from endpoint: NWEndpoint) async {
        // Extract IP address from endpoint
        let ipAddress: String
        let port: UInt16
        switch endpoint {
        case .hostPort(let host, let p):
            ipAddress = "\(host)"
            port = p.rawValue
        default:
            ipAddress = "unknown"
            port = UInt16(IPMSG_DEFAULT_PORT)
        }

        guard let packet = IPMsgPacketParser.parse(data: data, from: endpoint) else {
            logger.warning("Failed to parse packet from \(ipAddress) (\(data.count) bytes)")
            if let raw = String(data: data.prefix(200), encoding: .utf8) {
                logger.debug("  Raw: \(raw)")
            }
            return
        }

        let cmdMode = getMode(packet.command)
        logger.info("Received cmd=0x\(String(format: "%02X", cmdMode)) from \(packet.logOnUser)@\(ipAddress):\(port) appendix=\(packet.appendix.prefix(60))")

        // Skip messages from ourselves
        if ipAddress == HostInfo.primaryIPv4Address && packet.logOnUser == selfLogOnName {
            logger.debug("  Skipping own packet")
            return
        }

        // Lookup existing user or create temporary
        var fromUser = await userService.user(logOnName: packet.logOnUser, ipAddress: ipAddress)
        let isUnknownUser = (fromUser == nil)
        if fromUser == nil {
            fromUser = UserInfo(
                hostName: packet.hostName,
                logOnName: packet.logOnUser,
                ipAddress: ipAddress,
                port: port
            )
        }

        guard var fromUser else { return }

        let commandMode = getMode(packet.command)

        switch commandMode {
        // MARK: NOP
        case IPMsgCommand.noOperation.rawValue:
            break

        // MARK: BR_ENTRY / ANSENTRY / BR_ABSENCE
        case IPMsgCommand.brEntry.rawValue,
             IPMsgCommand.ansEntry.rawValue,
             IPMsgCommand.brAbsence.rawValue:
            await handleEntry(packet: packet, fromUser: &fromUser, ipAddress: ipAddress, port: port, isUnknownUser: isUnknownUser, commandMode: commandMode)

        // MARK: BR_EXIT
        case IPMsgCommand.brExit.rawValue:
            await userService.remove(id: fromUser.id)

        // MARK: SENDMSG
        case IPMsgCommand.sendMsg.rawValue:
            await handleSendMsg(packet: packet, fromUser: fromUser, ipAddress: ipAddress, isUnknownUser: isUnknownUser)

        // MARK: RECVMSG
        case IPMsgCommand.recvMsg.rawValue:
            if let pktNo = Int(packet.appendix) {
                await retryService.confirmReceived(packetNo: pktNo, from: fromUser.id)
            }

        // MARK: READMSG
        case IPMsgCommand.readMsg.rawValue:
            if packet.hasReadCheckOpt {
                await sendNumber(to: fromUser, command: IPMsgCommand.ansReadMsg.rawValue, number: packet.packetNo)
            }
            if settings.noticeSealOpened, let originalPacketNo = Int(packet.appendix) {
                eventContinuation?.yield(.sealOpened(fromUser: fromUser, packetNo: originalPacketNo))
            }

        // MARK: DELMSG / ANSREADMSG
        case IPMsgCommand.delMsg.rawValue,
             IPMsgCommand.ansReadMsg.rawValue:
            break

        // MARK: GETINFO
        case IPMsgCommand.getInfo.rawValue:
            await sendInfoResponse(to: fromUser)

        // MARK: SENDINFO
        case IPMsgCommand.sendInfo.rawValue:
            await userService.updateVersion(for: fromUser.id, version: packet.appendix)

        // MARK: GETABSENCEINFO
        case IPMsgCommand.getAbsenceInfo.rawValue:
            await sendAbsenceInfo(to: fromUser)

        // MARK: SENDABSENCEINFO
        case IPMsgCommand.sendAbsenceInfo.rawValue:
            break // Could display in UI

        // MARK: RELEASEFILES
        case IPMsgCommand.releaseFiles.rawValue:
            break // Handle in AttachmentStore

        // MARK: GETPUBKEY
        case IPMsgCommand.getPubKey.rawValue:
            await handleGetPubKey(packet: packet, fromUser: fromUser)

        // MARK: ANSPUBKEY
        case IPMsgCommand.ansPubKey.rawValue:
            await handleAnsPubKey(packet: packet, fromUser: fromUser)

        default:
            logger.warning("Unknown command: 0x\(String(format: "%08X", packet.command))")
        }
    }

    // MARK: - Entry Handling

    private func handleEntry(packet: IPMsgPacket, fromUser: inout UserInfo, ipAddress: String, port: UInt16, isUnknownUser: Bool, commandMode: UInt32) async {
        // Fingerprint + no encrypt = reject
        if fromUser.fingerPrint != nil && !packet.hasEncryptOpt {
            return
        }

        // Update user info — preserve cached crypto keys from the existing stored user
        if !isUnknownUser {
            let existingUser = fromUser
            fromUser = UserInfo(hostName: packet.hostName, logOnName: packet.logOnUser, ipAddress: ipAddress, port: port)
            fromUser.publicKey = existingUser.publicKey
            fromUser.cryptoCapability = existingUser.cryptoCapability
            fromUser.fingerPrint = existingUser.fingerPrint
        }
        fromUser.userName = packet.appendix
        fromUser.groupName = packet.appendixOption
        fromUser.inAbsence = packet.hasAbsenceOpt
        fromUser.dialupConnect = packet.hasDialupOpt
        fromUser.supportsAttachment = packet.hasFileAttachOpt
        fromUser.supportsEncrypt = packet.hasEncryptOpt
        fromUser.supportsEncExtMsg = packet.hasEncExtMsgOpt
        fromUser.supportsUTF8 = packet.hasCapUTF8Opt

        // Check refuse conditions (TODO: RefuseCondition matching)

        if commandMode == IPMsgCommand.brEntry.rawValue {
            // Send ANSENTRY with random delay
            let userCount = await userService.userCount
            let delay = Self.calculateEntryDelay(userCount: userCount)
            Task {
                try? await Task.sleep(for: .milliseconds(delay))
                await self.sendAnsEntry(to: ipAddress, port: port)
            }
        }

        // Add to user list
        await userService.addOrUpdate(fromUser)

        // Request version info
        await sendSimple(to: fromUser, command: IPMsgCommand.getInfo.rawValue)

        // Request public key if encryption supported
        if fromUser.supportsEncrypt, let crypto = cryptoService {
            let cap = await crypto.selfCapability
            let hasKey = fromUser.publicKey != nil
            NSLog("[CRYPTO] handleEntry: %@ supportsEncrypt=1 existingKey=%d — sending GETPUBKEY", fromUser.displayName, hasKey ? 1 : 0)
            await sendGetPubKey(to: fromUser, capability: cap.encode())
        } else {
            NSLog("[CRYPTO] handleEntry: %@ supportsEncrypt=%d — no key exchange needed", fromUser.displayName, fromUser.supportsEncrypt ? 1 : 0)
        }
    }

    // MARK: - Message Handling

    private func handleSendMsg(packet: IPMsgPacket, fromUser: UserInfo, ipAddress: String, isUnknownUser: Bool) async {
        // Send RECVMSG if requested
        if packet.hasSendCheckOpt && !packet.hasAutoRetOpt && !packet.hasBroadcastOpt {
            await sendNumber(to: fromUser, command: IPMsgCommand.recvMsg.rawValue, number: packet.packetNo)
        }

        // Auto-reply if in absence mode
        if settings.inAbsence && !packet.hasAutoRetOpt && !packet.hasBroadcastOpt {
            if let msg = settings.absenceMessage(at: settings.absenceIndex) {
                await sendMessage(
                    to: fromUser,
                    command: IPMsgCommand.sendMsg.rawValue | IPMsgOption.autoRetOpt.rawValue,
                    message: msg,
                    option: nil
                )
            }
        }

        // If unknown user, send BR_ENTRY to add to list
        if isUnknownUser && !packet.hasNoAddListOpt {
            await broadcastEntryTo(ipAddress: ipAddress)
        }

        // Decrypt if encrypted
        var messageText = packet.appendix
        var secureLevel = 0
        var doubt = false
        var decryptedOptionData: Data?

        let hasEncrypt = packet.hasEncryptOpt
        NSLog("[CRYPTO] handleSendMsg from=%@ cmd=0x%08X hasEncrypt=%d hasCrypto=%d appendixLen=%d", fromUser.displayName, packet.command, hasEncrypt ? 1 : 0, self.cryptoService != nil ? 1 : 0, packet.appendix.count)

        if hasEncrypt {
            if let crypto = cryptoService {
                let result = await crypto.decryptMessage(
                    appendix: packet.appendix,
                    packetNo: packet.packetNo,
                    senderPublicKey: fromUser.publicKey,
                    useUTF8: packet.hasUTF8Opt
                )
                if let result {
                    messageText = result.plainText
                    secureLevel = result.secureLevel
                    doubt = result.doubt
                    decryptedOptionData = result.optionData
                    NSLog("[CRYPTO] Decryption OK: secureLevel=%d textLen=%d", secureLevel, messageText.count)
                } else {
                    messageText = "[Encrypted message — decryption failed. The sender may need to restart their client to re-exchange keys.]"
                    doubt = true
                    let pubKeyInfo = fromUser.publicKey.map { "exp=0x\(String(format: "%X", $0.exponent)) mod=\($0.modulus.count)bytes keySizeInBits=\($0.keySizeInBits)" } ?? "nil"
                    NSLog("[CRYPTO] Decryption FAILED for packet from %@ (pkt=%d). senderPubKey=%@ appendixLen=%d. See CryptoService logs above for details.", fromUser.displayName, packet.packetNo, pubKeyInfo, packet.appendix.count)

                    // Auto-recovery after decryption failure.
                    // Windows IPMSG caches our public key per-user and will NOT re-request it
                    // when it receives an ordinary BR_ENTRY (it already has a cached key).
                    // Unsolicited ANSPUBKEY pushes are also ignored.
                    // The ONLY reliable way to force a GETPUBKEY is: send BR_EXIT (which makes
                    // Windows remove us from its user list) then BR_ENTRY (which makes Windows
                    // treat us as a new user and send GETPUBKEY). We respond with our current
                    // RSA2048 key → Windows updates its cache → next message decrypts correctly.
                    NSLog("[CRYPTO] Decryption failure recovery: sending BR_EXIT+BR_ENTRY to %@ to force GETPUBKEY", fromUser.displayName)
                    await sendExitThenEntry(to: fromUser.ipAddress, port: fromUser.port)

                    // Notify the sender in plaintext so they know their cached key is stale.
                    // This shows up as a received message on their end and prompts them to restart.
                    let noticeText = "[IPMsgX] Decryption failed — your cached public key for this Mac is stale. Please restart IPMsg to re-exchange encryption keys."
                    let noticePktNo = await PacketNumberGenerator.shared.next()
                    let noticeCmd: UInt32 = IPMsgCommand.sendMsg.rawValue
                    let noticeData = IPMsgPacketBuilder.buildSendMsg(
                        packetNo: noticePktNo,
                        logOnUser: selfLogOnName,
                        hostName: selfHostName,
                        command: noticeCmd,
                        message: noticeText,
                        optionData: nil,
                        useUTF8: fromUser.supportsUTF8
                    )
                    try? await transport.send(data: noticeData, to: fromUser.ipAddress, port: fromUser.port)
                    NSLog("[CRYPTO] Sent plaintext key-stale notification to %@", fromUser.displayName)
                }
            } else {
                messageText = "[Encrypted message — encryption service not available.]"
                doubt = true
                NSLog("[CRYPTO] cryptoService is nil — cannot decrypt")
            }
        }

        // Parse attachments
        var attachments: [IPMsgAttachmentParser.ParsedAttachment] = []
        if packet.hasFileAttachOpt {
            // Attachment data may come from decrypted option or original option1
            if let optData = decryptedOptionData,
               let optStr = String(data: optData, encoding: .utf8) {
                attachments = IPMsgAttachmentParser.parseAttachmentList(optStr)
            } else if let opt = packet.appendixOption {
                attachments = IPMsgAttachmentParser.parseAttachmentList(opt)
            }
        }

        // Build received message
        let recvMsg = ReceivedMessage(
            packetNo: packet.packetNo,
            receiveDate: Date(),
            fromUser: fromUser,
            message: messageText,
            secureLevel: secureLevel,
            doubt: doubt,
            isSealed: packet.hasSecretOpt,
            isLocked: packet.hasPasswordOpt,
            isMulticast: packet.hasMulticastOpt,
            isBroadcast: packet.hasBroadcastOpt,
            isAbsenceReply: packet.hasAutoRetOpt,
            attachments: attachments
        )

        eventContinuation?.yield(.messageReceived(recvMsg))
    }

    // MARK: - Crypto Handling

    private func handleGetPubKey(packet: IPMsgPacket, fromUser: UserInfo) async {
        // Parse requester's capability as hex (correct behavior).
        // The original Mac client had a bug here: it used [appendix integerValue] (decimal)
        // on a hex string, always yielding 0 and thus always returning RSA1024. We now
        // correctly parse as hex and respond with RSA2048 when the requester supports it.
        let requesterCapa = UInt32(packet.appendix, radix: 16) ?? 0
        await sendOurPubKey(to: fromUser, requesterCapa: requesterCapa, context: "handleGetPubKey")
    }

    /// Send our RSA public key to `user`. Call in response to GETPUBKEY or proactively after
    /// decryption failure to force the Windows client to update its cached key.
    private func sendOurPubKey(to user: UserInfo, requesterCapa: UInt32, context: String) async {
        guard let crypto = cryptoService else { return }
        let selfCap = await crypto.selfCapability
        guard selfCap.supportEncryption else { return }

        let requesterWantsRSA2048 = (requesterCapa & IPMsgEncFlag.rsa2048.rawValue) != 0
        let key: (exponent: UInt32, modulus: Data)?
        let keySize: String
        if requesterWantsRSA2048, let k = await crypto.publicKey2048 {
            key = k
            keySize = "RSA2048"
        } else if let k = await crypto.publicKey1024 {
            key = k
            keySize = "RSA1024"
        } else {
            key = await crypto.publicKey2048
            keySize = "RSA2048 (fallback)"
        }

        let selfCapa = selfCap.encode()

        guard let key else {
            NSLog("[CRYPTO] %@: no %@ key available — cannot send pubkey", context, keySize)
            return
        }

        let modulusHex = key.modulus.hexEncodedString
        NSLog("[CRYPTO] %@: sending %@ to %@ — requesterCapa=0x%X wantsRSA2048=%d selfCapa=0x%X modBytes=%d exp=0x%X", context, keySize, user.displayName, requesterCapa, requesterWantsRSA2048 ? 1 : 0, selfCapa, key.modulus.count, key.exponent)

        let packetNo = await PacketNumberGenerator.shared.next()
        let data = IPMsgPacketBuilder.buildPubKeyResponse(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            capability: selfCapa,
            exponent: key.exponent,
            modulusHex: modulusHex
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    private func handleAnsPubKey(packet: IPMsgPacket, fromUser: UserInfo) async {
        // Parse "capability:exponent-modulusHex"
        let parts = packet.appendix.components(separatedBy: ":")
        guard parts.count >= 2 else {
            NSLog("[CRYPTO] handleAnsPubKey: invalid format — only %d parts", parts.count)
            return
        }

        let capaVal = UInt32(parts[0], radix: 16) ?? 0
        let capability = CryptoCapability.decode(capaVal)

        let keyParts = parts[1].components(separatedBy: "-")
        guard keyParts.count == 2 else {
            NSLog("[CRYPTO] handleAnsPubKey: invalid key format — need exp-mod, got %d parts", keyParts.count)
            return
        }

        let exponent = UInt32(keyParts[0], radix: 16) ?? 0
        guard let modulus = Data(hexString: keyParts[1]) else {
            NSLog("[CRYPTO] handleAnsPubKey: invalid modulus hex (len=%d)", keyParts[1].count)
            return
        }

        let keyInfo = RSAPublicKeyInfo(exponent: exponent, modulus: modulus)
        NSLog("[CRYPTO] handleAnsPubKey from %@: capa=0x%X exp=0x%X modBytes=%d keySizeInBits=%d", fromUser.displayName, capaVal, exponent, modulus.count, keyInfo.keySizeInBits)

        // Calculate fingerprint
        var fingerPrint: Data?
        if capability.supportFingerPrint, let crypto = cryptoService {
            fingerPrint = await crypto.calculateFingerPrint(modulus: modulus)
        }

        await userService.updatePublicKey(for: fromUser.id, key: keyInfo, capability: capability, fingerPrint: fingerPrint)

        // Send any pending messages for this user
        let pending = await retryService.pendingMessages(for: fromUser.id)
        for retry in pending {
            await resendPendingMessage(retry, to: fromUser)
        }
    }

    private func resendPendingMessage(_ retry: RetryInfo, to user: UserInfo) async {
        // Re-send with encryption now that we have the public key
        _ = await sendMessagePacket(
            to: user,
            packetNo: retry.packetNo,
            command: retry.command,
            message: retry.message,
            option: retry.option
        )
    }

    // MARK: - Broadcasting

    func broadcastEntry() async {
        let packetNo1 = await PacketNumberGenerator.shared.next()
        let nopData = IPMsgPacketBuilder.buildPacket(
            packetNo: packetNo1,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.noOperation.rawValue
        )

        let packetNo2 = await PacketNumberGenerator.shared.next()
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName
        let absenceTitle = settings.inAbsence ? settings.absenceTitle(at: settings.absenceIndex) : nil
        let entryData = IPMsgPacketBuilder.buildEntry(
            packetNo: packetNo2,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brEntry.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: absenceTitle,
            fingerprint: selfFingerprint
        )

        let discoveredAddrs = BroadcastAddressResolver.allBroadcastAddresses
        let configuredAddrs = settings.broadcastAddresses
        let addresses = discoveredAddrs + configuredAddrs
        logger.info("Broadcasting BR_ENTRY as \(userName) (\(self.selfLogOnName)@\(self.selfHostName))")
        logger.info("  Discovered broadcast addresses: \(discoveredAddrs)")
        logger.info("  Configured broadcast addresses: \(configuredAddrs)")
        logger.info("  Self IP: \(HostInfo.primaryIPv4Address ?? "unknown")")
        logger.info("  Self spec: 0x\(String(format: "%08X", self.selfSpec))")
        if let entryStr = String(data: entryData, encoding: .utf8) {
            logger.debug("  Entry packet: \(entryStr)")
        }
        await transport.broadcast(data: nopData, toAddresses: addresses)
        await transport.broadcast(data: entryData, toAddresses: addresses)
    }

    func broadcastAbsence() async {
        // Update spec
        if settings.inAbsence {
            selfSpec |= IPMsgOption.absenceOpt.rawValue
        } else {
            selfSpec &= ~IPMsgOption.absenceOpt.rawValue
        }

        let packetNo = await PacketNumberGenerator.shared.next()
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName
        let absenceTitle = settings.inAbsence ? settings.absenceTitle(at: settings.absenceIndex) : nil
        let data = IPMsgPacketBuilder.buildEntry(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brAbsence.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: absenceTitle,
            fingerprint: selfFingerprint
        )

        let addresses = BroadcastAddressResolver.allBroadcastAddresses + settings.broadcastAddresses
        await transport.broadcast(data: data, toAddresses: addresses)
    }

    func broadcastExit() async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName
        let data = IPMsgPacketBuilder.buildEntry(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brExit.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: nil
        )

        let addresses = BroadcastAddressResolver.allBroadcastAddresses + settings.broadcastAddresses
        await transport.broadcast(data: data, toAddresses: addresses)
    }

    /// Send BR_EXIT then BR_ENTRY to a specific host, forcing it to clear its user-list entry
    /// for us and re-discover us as a new user. This is the only reliable way to make a Windows
    /// IPMSG client send GETPUBKEY for us again when it has a stale cached public key.
    private func sendExitThenEntry(to ipAddress: String, port: UInt16) async {
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName

        // BR_EXIT — Windows removes us from its user list
        let exitPktNo = await PacketNumberGenerator.shared.next()
        let exitData = IPMsgPacketBuilder.buildEntry(
            packetNo: exitPktNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brExit.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: nil
        )
        try? await transport.send(data: exitData, to: ipAddress, port: port)
        NSLog("[CRYPTO] sendExitThenEntry: sent BR_EXIT to %@:%d", ipAddress, port)

        // Brief pause so EXIT is processed before ENTRY arrives
        try? await Task.sleep(for: .milliseconds(200))

        // BR_ENTRY — Windows sees us as new, sends GETPUBKEY
        let entryPktNo = await PacketNumberGenerator.shared.next()
        let entryData = IPMsgPacketBuilder.buildEntry(
            packetNo: entryPktNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brEntry.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: nil,
            fingerprint: selfFingerprint
        )
        try? await transport.send(data: entryData, to: ipAddress, port: port)
        NSLog("[CRYPTO] sendExitThenEntry: sent BR_ENTRY to %@:%d — expecting GETPUBKEY in response", ipAddress, port)
    }

    private func broadcastEntryTo(ipAddress: String) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName
        let data = IPMsgPacketBuilder.buildEntry(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.brEntry.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: nil,
            fingerprint: selfFingerprint
        )
        try? await transport.send(data: data, to: ipAddress)
    }

    private func sendAnsEntry(to ipAddress: String, port: UInt16) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let userName = settings.userName.isEmpty ? selfLogOnName : settings.userName
        let data = IPMsgPacketBuilder.buildEntry(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: IPMsgCommand.ansEntry.rawValue | selfSpec,
            userName: userName,
            groupName: settings.groupName.isEmpty ? nil : settings.groupName,
            absenceTitle: settings.inAbsence ? settings.absenceTitle(at: settings.absenceIndex) : nil,
            fingerprint: selfFingerprint
        )
        try? await transport.send(data: data, to: ipAddress, port: port)
    }

    // MARK: - Sending Messages

    func sendMessage(to users: [UserInfo], message: String, isSealed: Bool, isLocked: Bool, attachments: [URL]) async -> Int {
        let packetNo = await PacketNumberGenerator.shared.next()

        var command: UInt32 = IPMsgCommand.sendMsg.rawValue | IPMsgOption.sendCheckOpt.rawValue
        if users.count > 1 {
            command |= IPMsgOption.multicastOpt.rawValue
        }
        if isSealed {
            command |= IPMsgOption.secretOpt.rawValue
            if isLocked {
                command |= IPMsgOption.passwordOpt.rawValue
            }
        }

        // Build attachment option and register with store for TCP serving
        var attachmentOption: String?
        if !attachments.isEmpty {
            var entries: [IPMsgAttachmentBuilder.AttachmentEntry] = []
            let fm = FileManager.default
            let userIDs = Set(users.map(\.id))
            for url in attachments {
                guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { continue }
                let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
                let size = (attrs[.size] as? UInt64) ?? 0
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                let isHidden = url.lastPathComponent.hasPrefix(".")
                // Register with store — fileID is assigned by the store
                let fileID = await attachmentStore.addAttachment(
                    packetNo: packetNo,
                    path: url,
                    users: userIDs
                )
                entries.append(IPMsgAttachmentBuilder.AttachmentEntry(
                    fileID: fileID,
                    fileName: url.lastPathComponent,
                    fileSize: size,
                    modifyTime: modDate,
                    isDirectory: isDir,
                    isReadOnly: false,
                    isHidden: isHidden,
                    isExtensionHidden: false,
                    posixPermissions: nil
                ))
            }
            if !entries.isEmpty {
                attachmentOption = IPMsgAttachmentBuilder.buildAttachmentAppendix(entries: entries)
                command |= IPMsgOption.fileAttachOpt.rawValue
            }
        }

        for user in users {
            // If encryption supported but no key yet, request key and queue message
            if user.supportsEncrypt && user.publicKey == nil {
                if let crypto = cryptoService {
                    let cap = await crypto.selfCapability
                    await sendGetPubKey(to: user, capability: cap.encode())
                }
                // Queue for retry
                let retry = RetryInfo(
                    packetNo: packetNo,
                    command: command,
                    toUser: user.id,
                    message: message,
                    option: attachmentOption
                )
                await retryService.addPending(retry)
            } else {
                _ = await sendMessagePacket(
                    to: user,
                    packetNo: packetNo,
                    command: command,
                    message: message,
                    option: attachmentOption
                )

                // Add to retry queue
                let retry = RetryInfo(
                    packetNo: packetNo,
                    command: command,
                    toUser: user.id,
                    message: message,
                    option: attachmentOption
                )
                await retryService.addPending(retry)
                startRetryTimer(for: retry)
            }
        }

        eventContinuation?.yield(.messageSent(packetNo: packetNo, toUsers: users))
        return packetNo
    }

    private func sendMessagePacket(to user: UserInfo, packetNo: Int, command: UInt32, message: String, option: String?) async -> Int {
        let useUTF8 = user.supportsUTF8

        // Try encryption if supported and enabled in settings
        if settings.encryptionEnabled, user.supportsEncrypt, let pubKey = user.publicKey, let crypto = cryptoService {
            let cap = user.cryptoCapability ?? CryptoCapability()
            let matchedCap = (await crypto.selfCapability).matched(with: cap)

            NSLog("[CRYPTO] sendMessagePacket → %@ supportsEncrypt=1 pubKeyBits=%d matchedCap=0x%X supportEncryption=%d", user.displayName, pubKey.keySizeInBits, matchedCap.encode(), matchedCap.supportEncryption ? 1 : 0)

            if matchedCap.supportEncryption {
                let encResult = await crypto.encryptMessage(
                    message: message,
                    option: option,
                    packetNo: packetNo,
                    recipientKey: pubKey,
                    capability: matchedCap,
                    supportsEncExtMsg: user.supportsEncExtMsg,
                    useUTF8: useUTF8
                )

                if let encResult {
                    var encCommand = command | IPMsgOption.encryptOpt.rawValue
                    if encResult.encExtMsg {
                        encCommand |= IPMsgOption.encExtMsgOpt.rawValue
                    }
                    NSLog("[CRYPTO] sendMessagePacket → %@: encryption OK, sending encrypted packet (pkt=%d)", user.displayName, packetNo)
                    let data = IPMsgPacketBuilder.buildEncryptedMsg(
                        packetNo: packetNo,
                        logOnUser: selfLogOnName,
                        hostName: selfHostName,
                        command: encCommand,
                        encryptedAppendix: encResult.encryptedAppendix,
                        plainOption: encResult.plainOptionData,
                        encExtMsg: encResult.encExtMsg,
                        useUTF8: useUTF8
                    )
                    try? await transport.send(data: data, to: user.ipAddress, port: user.port)
                    return packetNo
                } else {
                    NSLog("[CRYPTO] sendMessagePacket → %@: encryptMessage FAILED — falling back to plain text!", user.displayName)
                }
            } else {
                NSLog("[CRYPTO] sendMessagePacket → %@: matched capability does not support encryption — sending plain text", user.displayName)
            }
        } else {
            NSLog("[CRYPTO] sendMessagePacket → %@: supportsEncrypt=%d hasPublicKey=%d hasCrypto=%d — sending plain text", user.displayName, user.supportsEncrypt ? 1 : 0, user.publicKey != nil ? 1 : 0, cryptoService != nil ? 1 : 0)
        }

        // Plain text send
        let optData: Data?
        if let option {
            optData = StringEncoding.encode(string: option, utf8: useUTF8, nullTerminate: true)
        } else {
            optData = nil
        }

        let data = IPMsgPacketBuilder.buildSendMsg(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: command,
            message: message,
            optionData: optData,
            useUTF8: useUTF8
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
        return packetNo
    }

    // MARK: - Send Helpers

    private func sendSimple(to user: UserInfo, command: UInt32) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let data = IPMsgPacketBuilder.buildPacket(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: command
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    private func sendNumber(to user: UserInfo, command: UInt32, number: Int) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let appendix = "\(number)"
        let data = IPMsgPacketBuilder.buildPacket(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: command,
            appendixData: Data(appendix.utf8)
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    private func sendMessage(to user: UserInfo, command: UInt32, message: String, option: String?) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let useUTF8 = user.supportsUTF8
        let optData: Data?
        if let option {
            optData = StringEncoding.encode(string: option, utf8: useUTF8, nullTerminate: true)
        } else {
            optData = nil
        }
        let data = IPMsgPacketBuilder.buildSendMsg(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            command: command,
            message: message,
            optionData: optData,
            useUTF8: useUTF8
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    private func sendInfoResponse(to user: UserInfo) async {
        let packetNo = await PacketNumberGenerator.shared.next()
        let data = IPMsgPacketBuilder.buildInfoResponse(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            versionInfo: selfVersion
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    private func sendAbsenceInfo(to user: UserInfo) async {
        let message: String
        if settings.inAbsence, let msg = settings.absenceMessage(at: settings.absenceIndex) {
            message = msg
        } else {
            message = "Not Absence Mode."
        }
        await sendMessage(to: user, command: IPMsgCommand.sendAbsenceInfo.rawValue, message: message, option: nil)
    }

    private func sendGetPubKey(to user: UserInfo, capability: UInt32) async {
        NSLog("[CRYPTO] sendGetPubKey → %@ (%@) capability=0x%X", user.displayName, user.ipAddress, capability)
        let packetNo = await PacketNumberGenerator.shared.next()
        let data = IPMsgPacketBuilder.buildGetPubKey(
            packetNo: packetNo,
            logOnUser: selfLogOnName,
            hostName: selfHostName,
            capability: capability
        )
        try? await transport.send(data: data, to: user.ipAddress, port: user.port)
    }

    // MARK: - Open Seal

    func sendOpenSeal(to user: UserInfo, packetNo: Int) async {
        var command = IPMsgCommand.readMsg.rawValue
        if settings.noticeSealOpened {
            command |= IPMsgOption.readCheckOpt.rawValue
        }
        await sendNumber(to: user, command: command, number: packetNo)
    }

    // MARK: - Retry Logic

    private static let retryInterval: TimeInterval = 2.0
    private static let retryMax: Int = 3

    private func startRetryTimer(for retry: RetryInfo) {
        Task {
            for attempt in 1...Self.retryMax {
                try? await Task.sleep(for: .seconds(Self.retryInterval))
                let stillPending = await retryService.isPending(packetNo: retry.packetNo, toUser: retry.toUser)
                guard stillPending else { return }

                logger.info("Retry \(attempt)/\(Self.retryMax) for packet \(retry.packetNo)")
                if attempt >= Self.retryMax {
                    await retryService.removePending(packetNo: retry.packetNo, toUser: retry.toUser)
                    eventContinuation?.yield(.sendRetryFailed(
                        packetNo: retry.packetNo,
                        toUser: UserInfo(hostName: "", logOnName: retry.toUser.logOnName, ipAddress: retry.toUser.ipAddress)
                    ))
                }
            }
        }
    }

    // MARK: - Entry Delay Calculation

    static func calculateEntryDelay(userCount: Int) -> Int {
        if userCount < 50 {
            return Int.random(in: 0...1023)
        } else if userCount < 300 {
            return Int.random(in: 0...2047)
        } else {
            return Int.random(in: 0...4095)
        }
    }
}
