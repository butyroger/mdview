## 安裝

1. 下載 `MDView-x.x.dmg`，打開後把 **MDView** 拖到「應用程式」。
2. 第一次開啟：本程式未經 Apple 公證，macOS 會擋。請到「系統設定 → 隱私權與安全性」最下方按「強制打開」；或在終端機執行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/MDView.app
   ```
3. 開啟一次 MDView 後，會自動完成 Quick Look 預覽外掛與連結中繼的設定。
4. 要讓雙擊 `.md` 用 MDView 開：對任一 `.md` 按右鍵 →「取得資訊」→「打開檔案的應用程式」選 MDView →「全部更改」。

需求：macOS 12 以上（Apple 晶片與 Intel 皆可）。
