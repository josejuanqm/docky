//
//  DividerTileView.swift
//  Docky
//

import SwiftUI

struct DividerTileView: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.2))
            .frame(width: 1)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background {
                ContextActionMenuPresenter(actions: [
                    .action("Settings...") {
                        (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
                    },
                    .divider,
                    .action("Quit Docky", isDestructive: true) {
                        NSApp.terminate(nil)
                    }
                ])
            }
    }
}
