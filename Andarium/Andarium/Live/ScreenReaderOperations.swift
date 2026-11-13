// SPDX-License-Identifier: GPL-2.0-or-later

import AndariumCore
import Foundation

nonisolated extension AdbGuestOperations {
    /// TalkBack in the guest; nil when the guest cannot be asked now.
    func screenReader() async -> ScreenReaderState? {
        guard let result = try? await shell(ScreenReader.stateCommand, limit: .seconds(15)) else { return nil }
        return ScreenReader.parse(result)
    }

    /// Turns TalkBack on or off in the guest whose state is `state`, and
    /// returns the state Android reports after.
    func setScreenReader(_ on: Bool, in state: ScreenReaderState) async throws -> ScreenReaderState {
        guard let command = ScreenReader.command(turningOn: on, in: state) else {
            throw AdbFailure(message: ScreenReaderWords.missing)
        }
        let result: ShellResult
        do {
            result = try await shell(command, limit: .seconds(30))
        } catch {
            throw AdbOperationRunner.presented(error, activity: .screenReader)
        }
        guard result.exitCode == 0 else {
            let said = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AdbFailure(message: said.isEmpty ? AdbFailure(.io(EIO), activity: .screenReader).message : said)
        }
        return await screenReader() ?? ScreenReader.state(afterTurningOn: on, state)
    }

    /// Opens Android's Accessibility page on the guest's screen.
    func openAccessibilitySettings() async throws {
        do {
            _ = try await shell(ScreenReader.settingsCommand, limit: .seconds(15))
        } catch {
            throw AdbOperationRunner.presented(error, activity: .screenReader)
        }
    }
}
