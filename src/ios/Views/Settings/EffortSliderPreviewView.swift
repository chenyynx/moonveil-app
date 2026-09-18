//
//  EffortSliderPreviewView.swift
//  Settings preview page for the Ultracode flame slider.
//
//  Visual preview only — drag the thumb to 100 to ignite the fire. This is a
//  standalone gallery entry; no reasoning-effort logic is wired yet.
//

import SwiftUI

struct EffortSliderPreviewView: View {

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Drag the slider to 100. The track ignites with the Claude-style Ultracode flame, the status label flips in with a purple glow, and the thumb picks up a violet halo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                EffortCardView()
                    .padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ultracode Flame")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        EffortSliderPreviewView()
    }
}
