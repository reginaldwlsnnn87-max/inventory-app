# Pulse Remote

Elegant Wi-Fi TV remote for LG webOS TVs, built in SwiftUI.

## Core Features
- LG TV discovery on local network (Bonjour + fallback IP)
- Secure pairing and reconnect
- D-pad/ring + swipe controls
- Volume, mute, home, back, power controls
- Smart scenes and quick actions
- Lock screen/home widgets for fast commands

## Requirements
- Xcode 26.0+
- iOS 26.0+

## Run
1. Open `Pulse Remote.xcodeproj` in Xcode.
2. Select a simulator or connected iPhone.
3. Build and run the `Pulse Remote` scheme.

## Project Structure
- `Pulse Remote/TVRemote/` main remote app modules
- `Pulse Remote.xcodeproj/PulseRemoteWidgets/` widget extension
- `Pulse RemoteTests/` unit tests
- `Pulse RemoteUITests/` UI tests
