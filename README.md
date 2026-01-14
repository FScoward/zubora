# Zubora

Zuboraは、macOS向けのウィンドウ位置交換ユーティリティです。
デスクトップ上のウィンドウ配置を、直感的な操作で瞬時に入れ替えることができます。

## 特徴
- **簡単スワップ**: 2つのウィンドウの位置とサイズを瞬時に入れ替えます。
- **ゲーミングハイライト**: ターゲットとして登録したウィンドウは、美しい虹色のグラデーションでハイライトされます。
- **ローテーション機能**: ターゲットウィンドウを固定したまま、次々と他のウィンドウと位置を交換していくことができます。

## 使い方

### 1. ターゲットの登録
まず、基準となるウィンドウ（ターゲット）を決めます。
そのウィンドウをアクティブ（最前面）にした状態で、以下のショートカットを押します。

- **`Option` + `S`**

登録されると、ウィンドウの枠が虹色に光り始めます。

### 2. ウィンドウのスワップ
ターゲットウィンドウと位置を入れ替えたい別のウィンドウの上にマウスカーソルを移動させ、以下の操作を行います。

- **`Option` + `Control` + `Click` (左クリック)**

すると、ターゲットウィンドウとクリックしたウィンドウの位置・サイズが入れ替わります。
スワップ時には爽快なパーティクルエフェクトが表示されます。

## インストールとビルド
このアプリケーションはソースコードとして提供されています。以下の手順でビルドして使用してください。

### 必要要件
- macOS 13.0 (Ventura) 以降
- Xcode Command Line Tools (Swift 6.2以降推奨)

### ビルド手順

1. リポジトリをクローンします。
2. プロジェクトのルートディレクトリで以下のコマンドを実行し、配布用パッケージを作成します。
   ```bash
   ./package_app.sh
   ```
3. 生成された `Zubora.app` をアプリケーションフォルダなどに移動して起動してください。

### 開発用ビルド
開発中に試す場合は、以下のコマンドでリリースビルドを作成・実行できます。
```bash
swift build -c release
./.build/release/Zubora
```

## 注意事項
- 初回起動時、**アクセシビリティ権限**と**画面収録権限**（ウィンドウ情報の取得に必要）の許可を求められます。システム設定で許可を与えてください。
- **アップデート時の注意**: 本アプリはApple Developer IDで署名されていません。そのため、アプリをアップデートする（新しいバージョンに置き換える）たびに、macOSのセキュリティ仕様により権限設定がリセットされます。アップデート後は、システム設定から既存の権限設定を一度削除（-ボタン）し、再度追加・許可を行ってください。

---

# Zubora (English)

Zubora is a window position swapping utility for macOS.
It allows you to instantly swap the layout of windows on your desktop with intuitive operations.

## Features
- **Easy Swap**: Instantly swap the position and size of two windows.
- **Gaming Highlight**: The window registered as a target is highlighted with a beautiful rainbow gradient.
- **Rotation Function**: You can keep the target window fixed and swap its position with other windows one after another.

## How to Use

### 1. Register a Target
First, decide on a base window (target).
With that window active (in the foreground), press the following shortcut:

- **`Option` + `S`**

Once registered, the window frame will start to glow with a rainbow color.

### 2. Swap Windows
Move the mouse cursor over another window you want to swap positions with the target window, and perform the following operation:

- **`Option` + `Control` + `Click` (left-click)**

This will swap the position and size of the target window and the clicked window.
A refreshing particle effect will be displayed during the swap.

## Installation and Build
This application is provided as source code. Please build and use it according to the following steps.

### Requirements
- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (Swift 6.2 or later recommended)

### Build Steps

1. Clone the repository.
2. In the project root directory, run the following command to create a distribution package.
   ```bash
   ./package_app.sh
   ```
3. Move the generated `Zubora.app` to your Applications folder or another location and launch it.

### Development Build
For testing during development, you can create and run a release build with the following command:
```bash
swift build -c release
./.build/release/Zubora
```

## Notes
- On first launch, you will be asked to grant **Accessibility permissions** and **Screen Recording permissions** (required to get window information). Please grant these permissions in System Settings.
- **Note on Updates**: Since this app is not signed with an Apple Developer ID, permission settings will be reset by macOS security policies every time you update the app. After updating, please remove the existing permission entry (using the "-" button) in System Settings and re-add/grant permissions again.
