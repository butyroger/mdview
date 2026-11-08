# MDView

輕量的 macOS Markdown 閱讀器（Swift＋WKWebView），附 Quick Look 預覽外掛。

- 外部連結交給系統預設瀏覽器開啟；相對路徑的 `.md` 連結在 MDView 內開新視窗
- 檔案存檔後自動重新整理並保留捲動位置
- 工具列：開啟、目錄側欄、PDF、匯出（PDF／HTML／DOCX）、主題（跟隨系統／淺色／深色）、快捷鍵說明
- ⌘F 頁內搜尋（支援注音選字）
- Finder 空白鍵預覽：樣式、主題與 App 一致，連結可點

## 建置與安裝

```bash
./build.sh               # 編譯通用版（arm64＋x86_64，macOS 12+）並安裝到本機 ~/Applications
./build.sh --no-install  # 只編譯到 build/MDView.app
./deploy.sh [host ...]   # 編譯後經 SSH 部署到其他 Mac（不帶參數時讀 deploy-hosts.txt）
```

`install.sh` 會：安裝 App、註冊並啟用 Quick Look 外掛、停用並移除舊的 MD Viewer／QLMarkdown、建立連結中繼 LaunchAgent、把 `.md` 預設開啟程式設為 MDView。

## 為什麼要連結中繼

Quick Look 外掛在沙盒裡既不能直接開啟其他程式（缺 Apple 私有 entitlement），也不能連網。預覽裡點連結時，外掛透過 XPC mach 服務 `com.butyshop.mdview.linkhelper` 請 LaunchAgent 啟動的 `MDView --link-helper` 代為開啟（只接受 http／https／mailto／file）。

## 第三方元件

- [markdown-it](https://github.com/markdown-it/markdown-it) 13.0.2（MIT）
- [markdown-it-task-lists](https://github.com/revin/markdown-it-task-lists) 2.1.1（ISC）
