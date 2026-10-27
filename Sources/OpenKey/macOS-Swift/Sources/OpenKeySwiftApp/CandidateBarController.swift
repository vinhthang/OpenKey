//
//  CandidateBarController.swift
//  OpenKeySwiftApp
//
//  Created for OpenKey macOS Swift.
//  Non-Activating Floating Candidate Bar with macOS 26 Liquid Glass (.glassEffect).
//

import Cocoa
import SwiftUI
import ApplicationServices
import OpenKeySwiftCore

// MARK: - SwiftUI Candidate Bar View

struct CandidateBarView: View {
    let candidates: [WordCandidate]
    let onSelect: (WordCandidate) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                Button(action: {
                    onSelect(candidate)
                }) {
                    HStack(spacing: 6) {
                        Text(badgeForIndex(index))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.18))
                            .cornerRadius(4)
                        
                        Text(candidate.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if index < candidates.count - 1 {
                    Divider()
                        .frame(height: 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
    
    private func badgeForIndex(_ index: Int) -> String {
        if index == 0 { return "Tab" }
        return "⌃\(index + 1)"
    }
}

// MARK: - Candidate Bar Controller (REQ-006)

@MainActor
public final class CandidateBarController: ObservableObject {
    public static let shared = CandidateBarController()
    
    private var panel: NSPanel?
    private var isStarted = false
    private var updateWorkItem: DispatchWorkItem?
    private var hostingView: NSHostingView<CandidateBarView>?
    
    public init() {}
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        setupPanel()
        
        AutoWordingEngine.shared.onCandidatesChanged = { [weak self] candidates in
            guard let self = self else { return }
            self.handleCandidatesUpdated(candidates)
        }
    }
    
    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // Handled inside SwiftUI glass view
        p.isMovableByWindowBackground = false
        p.ignoresMouseEvents = false
        
        self.panel = p
    }
    
    private func handleCandidatesUpdated(_ candidates: [WordCandidate]) {
        updateWorkItem?.cancel()
        updateWorkItem = nil
        
        guard let panel = panel else { return }
        
        if candidates.isEmpty {
            panel.orderOut(nil)
            return
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            
            let candidateView = CandidateBarView(candidates: candidates) { [weak self] selected in
                self?.acceptCandidate(selected)
            }
            
            if let existingHostingView = self.hostingView {
                existingHostingView.rootView = candidateView
            } else {
                let newHostingView = NSHostingView(rootView: candidateView)
                newHostingView.translatesAutoresizingMaskIntoConstraints = false
                panel.contentView = newHostingView
                self.hostingView = newHostingView
            }
            
            guard let currentHostingView = self.hostingView else { return }
            let fittingSize = currentHostingView.fittingSize
            let caretPoint = CaretPositionResolver.resolveCaretScreenPoint()
            
            // Clamp to screen bounds of active display (REQ-003, ADR-003)
            let targetScreen = CaretPositionResolver.screenContaining(point: caretPoint)
            let screenFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            var targetX = caretPoint.x
            var targetY = caretPoint.y - fittingSize.height
            
            if targetX + fittingSize.width > screenFrame.maxX {
                targetX = screenFrame.maxX - fittingSize.width - 10
            }
            if targetX < screenFrame.minX {
                targetX = screenFrame.minX + 10
            }
            if targetY < screenFrame.minY {
                targetY = caretPoint.y + 24 // Flip above caret if bottom of screen
            }
            
            panel.setFrame(NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height), display: true)
            panel.orderFront(nil)
        }
        
        self.updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60), execute: workItem)
    }
    
    private func acceptCandidate(_ candidate: WordCandidate) {
        AutoWordingEngine.shared.recordCandidateAcceptance(text: candidate.text)
        let fullText = candidate.text + " "
        let chars = Array(fullText.utf16)
        KeystrokeInjector.shared.injectReplacementWithoutProxy(
            backspaceCount: candidate.replaceLength,
            chars: chars
        )
        OKEngineResetSession()
        let nextCands = AutoWordingEngine.shared.computeNextWordCandidates(previousWord: candidate.text)
        AutoWordingEngine.shared.updateCandidates(nextCands)
    }
}
