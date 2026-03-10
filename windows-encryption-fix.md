# Windows Encryption Fix — Clearing Stale Keys from Registry

If Windows IP Messenger cannot decrypt messages from IPMsgX (or shows `(RSA2/Impersonate?)` in its log), it means Windows has a stale cached public key for this Mac. Follow these steps to clear it.

## Why this happens

Windows IP Messenger caches RSA public keys in the registry. If the Mac's keys were regenerated (e.g. after using **Reset Encryption Keys** in IPMsgX Settings), Windows still holds the old key in memory and in the registry. It will not request a fresh key until it is restarted with the old registry entries removed.

## Steps to fix

### 1. Quit IP Messenger on Windows

Right-click the IP Messenger tray icon → **Exit** (or **Quit**). The app must be fully closed — not just minimized.

### 2. Open Registry Editor

Press **Win + R**, type `regedit`, press **Enter**. Click **Yes** if prompted by UAC.

### 3. Navigate to the IP Messenger key

In the left panel, expand:

```
HKEY_CURRENT_USER
  └─ Software
       └─ HSTools
            └─ IPMsgEng
```

Click on the **IPMsgEng** folder to select it.

### 4. Delete the three stale entries

In the right panel, locate and delete each of the following values:

| Value name  | What it stores                        |
|-------------|---------------------------------------|
| `crypt`     | Cached RSA-1024 public key for this Mac |
| `crypt2`    | Cached RSA-2048 public key for this Mac |
| `hostinfo2` | Cached host/fingerprint info for this Mac |

To delete a value: **right-click** the entry → **Delete** → **Yes**.

> **Tip:** If you want a clean slate, you can delete the entire `IPMsgEng` key. This removes cached keys for all hosts, not just this Mac.

### 5. Close Registry Editor and reopen IP Messenger

Once IP Messenger starts, it will detect IPMsgX as a new user and automatically request a fresh public key via `GETPUBKEY`. Encryption will work correctly from that point on.

## Alternative: use IPMsgX's built-in recovery

IPMsgX v1.1+ automatically attempts key re-exchange when decryption fails. If the Windows side is online and IPMsgX sends a message, the re-exchange is triggered automatically — the steps above are only needed when automatic recovery does not succeed (e.g. the Windows client is offline during the re-exchange attempt).

You can also disable encryption entirely from IPMsgX **Settings → Network → Enable message encryption** as a temporary workaround while troubleshooting.
