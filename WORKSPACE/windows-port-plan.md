# IPMsgX — Windows Port Plan

**Target:** Windows 11, 64-bit only
**UI Paradigm:** Fluent Design System (Windows 11 native)
**Date:** March 2026

---

## Platform Decision

### Options Evaluated

| Option | Maintenance | Runtime Footprint | Native UI | macOS Stability | Windows Stability |
|---|---|---|---|---|---|
| Go + Fyne | Simple | Excellent (single binary) | ❌ Not native | Good | Good |
| Qt 6 + C++ | Complex | Heavy (~50–100MB frameworks) | ✅ Native per platform | Excellent | Excellent |
| **WinUI 3 + C#** | **Simple** | **Good (MSIX/portable)** | **✅ Windows 11 native** | N/A | **Excellent** |

### Decision: WinUI 3 (Windows App SDK) with C#

Since the target is **Windows 11 only**, WinUI 3 is Microsoft's current native UI framework — the same foundation used by Windows 11 inbox apps (Settings, Mail, File Explorer). It implements the Fluent Design System natively and maps directly to the existing SwiftUI layout patterns in IPMsgX.

C# is chosen over C++/WinRT because:
- Syntax and async patterns are closest to Swift — existing team knowledge transfers directly
- `.NET System.Security.Cryptography` covers all RSA and AES needs out of the box
- Significantly less boilerplate than C++/WinRT for equivalent results

---

## UI Layout Mapping

The existing IPMsgX SwiftUI structure maps cleanly to WinUI 3 equivalents:

| SwiftUI (macOS) | WinUI 3 (Windows) | Notes |
|---|---|---|
| `NavigationSplitView` | `NavigationView` | Identical sidebar + detail pattern |
| `List` (user rows) | `ListView` | Same selection model |
| `@Observable` / `@Published` | `[ObservableProperty]` (CommunityToolkit.Mvvm) | Same reactive data flow |
| `actor` (concurrency) | `async`/`await` + thread-safe collections | Direct equivalent |
| `.sheet` | `ContentDialog` | Modal dialogs |
| `.toolbar` | `CommandBar` | Top action bar |
| `SwiftUI.Window` | `Microsoft.UI.Xaml.Window` | App window |
| Settings scene | `SettingsPage` via NavigationView | Settings item built into NavigationView |

### XAML Example — Sidebar Layout

```xml
<!-- WinUI 3 — maps to IPMsgX's NavigationSplitView -->
<NavigationView PaneDisplayMode="Left"
                IsSettingsVisible="True"
                SelectionChanged="NavView_SelectionChanged">
    <NavigationView.MenuItems>
        <NavigationViewItem Content="Online Users"
                            Icon="People"
                            Tag="users"/>
    </NavigationView.MenuItems>
    <Frame x:Name="ContentFrame"/>
</NavigationView>
```

```swift
// Equivalent SwiftUI in current IPMsgX
NavigationSplitView {
    UserListView()
} detail: {
    ChatDetailView()
}
```

---

## Crypto Layer Mapping

All crypto operations in `CryptoService.swift` have direct C# equivalents. The Apple Security and CommonCrypto frameworks are replaced entirely by .NET's built-in `System.Security.Cryptography`.

| Current Swift (Apple APIs) | C# .NET Equivalent |
|---|---|
| `SecKeyCreateRandomKey` (RSA 1024/2048) | `RSA.Create(1024)` / `RSA.Create(2048)` |
| `SecKeyCreateEncryptedData` (PKCS1v1.5) | `rsa.Encrypt(data, RSAEncryptionPadding.Pkcs1)` |
| `SecKeyCreateDecryptedData` (PKCS1v1.5) | `rsa.Decrypt(data, RSAEncryptionPadding.Pkcs1)` |
| `SecKeyCreateSignature` (SHA256/SHA1) | `rsa.SignData(data, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)` |
| `SecKeyVerifySignature` | `rsa.VerifyData(data, sig, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)` |
| `CCCrypt` AES-256-CBC | `Aes.Create()` with `CipherMode.CBC`, `PaddingMode.PKCS7` |
| `CCCrypt` Blowfish-128-CBC | `BouncyCastle.Cryptography` NuGet package |
| `SecRandomCopyBytes` | `RandomNumberGenerator.GetBytes(n)` |
| Key persistence (file-based DER) | Same file-based approach, or `ProtectedData` (Windows DPAPI) |
| `SecKeyCopyExternalRepresentation` (DER) | `rsa.ExportRSAPrivateKey()` / `rsa.ExportRSAPublicKey()` |

### Blowfish Note

.NET does not include Blowfish in its standard crypto library. The `BouncyCastle.Cryptography` NuGet package is the standard solution — well-maintained, widely used, and covers Blowfish-CBC with PKCS7 padding identically to CommonCrypto's implementation.

---

## Networking Layer Mapping

| Current Swift (Apple Network) | C# .NET Equivalent |
|---|---|
| `NWConnection` (UDP) | `UdpClient` / `Socket` |
| Broadcast UDP send | `UdpClient.Send` to `255.255.255.255:2425` |
| Multicast | `UdpClient.JoinMulticastGroup` |
| Receive loop | `UdpClient.ReceiveAsync` in async loop |
| Port binding (2425) | `UdpClient(2425)` |

---

## Architecture — Recommended Structure

```
IPMsgXWin/
├── IPMsgXWin.csproj
├── App.xaml / App.xaml.cs
├── MainWindow.xaml / MainWindow.xaml.cs
│
├── Protocol/               # Port of IPMsgPacketBuilder/Parser
│   ├── IPMsgPacket.cs
│   ├── IPMsgPacketBuilder.cs
│   └── IPMsgPacketParser.cs
│
├── Crypto/                 # Port of CryptoService + SymmetricCrypto
│   ├── CryptoService.cs
│   ├── SymmetricCrypto.cs
│   └── RSAPublicKeyHelper.cs
│
├── Services/               # Port of MessageService, UserService
│   ├── MessageService.cs
│   ├── UserService.cs
│   ├── NetworkTransport.cs
│   └── RetryService.cs
│
├── Models/                 # Port of UserInfo, IPMsgPacket
│   ├── UserInfo.cs
│   ├── CryptoCapability.cs
│   └── IPMsgConstants.cs
│
└── Views/                  # WinUI 3 XAML pages
    ├── UserListPage.xaml
    ├── ChatPage.xaml
    └── SettingsPage.xaml
```

The Protocol, Crypto, Services, and Models layers are direct ports with no platform dependencies. Only the Views layer is platform-specific.

---

## Tooling

| Tool | Purpose |
|---|---|
| Visual Studio 2022 | IDE — WinUI 3 designer, XAML hot reload, C# debugger |
| Windows App SDK (NuGet) | WinUI 3 runtime |
| CommunityToolkit.Mvvm | MVVM data binding — equivalent to SwiftUI's data flow |
| BouncyCastle.Cryptography | Blowfish-128-CBC support |
| MSIX Packaging Tool | Distribution — produces signed installer |

---

## Key Protocol Considerations (from macOS port learnings)

These quirks were discovered during the macOS Swift port and must be replicated exactly on Windows:

1. **GETPUBKEY capability parsing bug** — The original Mac IP Messenger parses the hex capability string with a decimal parser (`integerValue`), always returning 0. This means it always responds with RSA1024 regardless of the requester's capabilities. The Windows port must match this: **always respond to GETPUBKEY with RSA1024**.

2. **RSA key fallback on decrypt** — When decrypting an incoming session key, validate the decrypted size matches the expected symmetric key size (32 bytes for AES-256, 16 bytes for Blowfish-128). If it doesn't match, try the other RSA key size. This handles clients that have a stale cached public key.

3. **Key persistence** — RSA key pairs must be persisted across restarts. If keys are regenerated, other clients' cached keys become invalid and decryption fails silently (Apple/Windows Security frameworks return garbage on wrong-key PKCS1v1.5 decrypt rather than an error, due to Bleichenbacher attack mitigation).

4. **Hex encoding is lowercase** — All modulus and session key hex strings must use lowercase `0–9a–f`. The original source uses lowercase throughout.

5. **IV from packet number** — When `IPMSG_PACKETNO_IV` flag is set, the IV is the ASCII string of the packet number, zero-padded to 32 bytes.

6. **Signing key** — The original code signs with the same key size as the recipient's public key. Use RSA2048 for signing when available.

---

## Distribution

- **MSIX package** — recommended for Windows 11; supports auto-update, clean uninstall, optional Store distribution
- **Portable EXE** — self-contained single-folder distribution via `dotnet publish --self-contained`; no installer required, good for enterprise/IT environments

---

## Effort Estimate (relative)

| Layer | Complexity | Notes |
|---|---|---|
| Protocol (packet build/parse) | Low | Direct port, no platform deps |
| Crypto | Low–Medium | Direct API mapping; Blowfish needs BouncyCastle |
| Networking (UDP) | Low | `UdpClient` is simpler than Apple's Network framework |
| UI | Medium | WinUI 3 XAML learning curve; layout is straightforward |
| Testing + interop | Medium | Verify against Windows IP Messenger and macOS IPMsgX |

---

## Development Environment

### Can We Use Xcode or VSCode?

**Xcode — No.** Xcode is Apple-only. It has no support for C#, WinUI 3, or Windows SDK. Not applicable.

**VSCode on macOS — Partially, but not enough to ship.**
VSCode runs on macOS and has good C# support via Microsoft's C# Dev Kit extension (writing, IntelliSense, refactoring). However, building hits a hard wall:

- WinUI 3 / Windows App SDK build tools are **Windows-only** — the XAML compiler, resource compiler, and Windows SDK linker do not exist for macOS
- The `.NET SDK` runs on macOS but `dotnet build` for a WinUI 3 project fails immediately — it requires Windows SDK components unavailable on macOS
- There is no cross-compilation path from macOS → WinUI 3 Windows binary

### What's Actually Needed: A Windows Environment

#### Option A — Windows VM on Mac (recommended)
Parallels Desktop or VMware Fusion running Windows 11 ARM on Apple Silicon. Performance is excellent — Windows 11 ARM runs near-native on M-series chips.

Inside the VM:
- **Visual Studio 2022 Community** (free) — best tool for WinUI 3; includes XAML designer, hot reload, full debugger
- Or **VSCode + C# Dev Kit + Windows App SDK** — lighter alternative if VSCode is preferred

Project folder can be shared between macOS and the VM so the existing editor workflow is preserved.

#### Option B — Separate Windows machine / cloud VM
Spin up a Windows PC or cloud VM (Azure, AWS), install Visual Studio 2022, and develop remotely using VSCode's **Remote SSH** extension — edit on macOS, builds run on Windows.

### Recommended Setup

```
macOS (primary machine)
└── Parallels Desktop / VMware Fusion
    └── Windows 11 ARM (VM)
        ├── Visual Studio 2022 Community  ← primary WinUI 3 IDE
        └── Windows App SDK + .NET 8 SDK
```

The Protocol, Crypto, and Services layers (pure C# with no platform UI dependencies) can be written in VSCode on either side. UI work is done inside the VM.

### Tool Capability Summary

| Tool | Write C# | Build WinUI 3 | Run / Debug |
|---|---|---|---|
| Xcode (macOS) | ❌ | ❌ | ❌ |
| VSCode (macOS) | ✅ | ❌ | ❌ |
| VSCode (Windows VM) | ✅ | ✅ | ✅ |
| Visual Studio 2022 (Windows VM) | ✅ | ✅ | ✅ (best experience) |
