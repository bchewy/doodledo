import PencilKit
import SwiftUI
import UIKit
import os

private let canvasLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "doodledo",
    category: "CanvasView"
)

struct CanvasView: View {
    @EnvironmentObject private var store: DoodleStore
    let entryID: UUID

    @State private var drawing = PKDrawing()
    @State private var caption = ""
    @State private var selectedTool = ToolKind.ink
    @State private var canvasTab: CanvasTab = .draw
    @State private var selectedInk = InkStyle.pen
    @State private var selectedColor: UIColor = .black
    @State private var selectedWidth: CGFloat = 6
    @AppStorage("openai_api_key") private var openAIAPIKey = ""
    @State private var isGenerating = false
    @State private var showAPIKeyEditor = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var canvasSize: CGSize = .zero
    @State private var selectionMode: SelectionMode = .fullCanvas
    @State private var selectionPoints: [CGPoint] = []
    @State private var selectionActive = false
    @State private var selectionClosed = false
    @State private var showMaskPreview = false
    @State private var selectedStyle: GenerationStyle = .cute

    private let selectionExpansion: CGFloat = 8
    private let generationPrompt = """
    Use the provided doodle as a guide. Preserve the silhouette, proportions, and composition. Re-ink the linework to match the requested style (no raw black sketch lines). Apply the style with cohesive colors and textures. Do not add or remove elements. No text.
    """

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white

                if let backgroundImage {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                DrawingCanvasView(drawing: $drawing, tool: currentTool) { newDrawing in
                    store.saveDrawing(newDrawing, for: entryID)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if canvasTab == .ai && selectionMode == .lasso {
                    LassoSelectionOverlay(
                        points: $selectionPoints,
                        isActive: $selectionActive,
                        isClosed: $selectionClosed
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
                }
            }
            .onAppear {
                canvasSize = proxy.size
            }
            .onChange(of: proxy.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .safeAreaInset(edge: .top) {
            CanvasControls(
                canvasTab: $canvasTab,
                selectedTool: $selectedTool,
                selectedInk: $selectedInk,
                selectedColor: $selectedColor,
                selectedWidth: $selectedWidth,
                selectionMode: $selectionMode,
                selectionActive: $selectionActive,
                selectedStyle: $selectedStyle,
                hasSelection: hasSelection,
                isGenerating: isGenerating,
                onGenerate: requestGenerate,
                onClearSelection: clearSelection,
                onPreviewSelection: { showMaskPreview = true },
                onRedrawSelection: startRedraw
            )
        }
        .safeAreaInset(edge: .bottom) {
            CaptionEditor(text: $caption)
        }
        .onAppear {
            if let entry = store.entry(for: entryID) {
                caption = entry.caption
            } else {
                caption = ""
            }
            drawing = store.loadDrawing(for: entryID)
        }
        .onChange(of: caption) { _, newValue in
            store.updateCaption(newValue, for: entryID)
        }
        .onChange(of: selectionActive) { _, newValue in
            if !newValue {
                selectionClosed = selectionPoints.count > 2
            }
        }
        .onChange(of: canvasTab) { _, newValue in
            if newValue != .ai {
                selectionActive = false
                showMaskPreview = false
            }
        }
        .onChange(of: selectionMode) { _, newValue in
            if newValue != .lasso {
                selectionActive = false
                showMaskPreview = false
            }
        }
        .onDisappear {
            store.saveDrawing(drawing, for: entryID, generateThumbnail: true)
        }
        .sheet(isPresented: $showAPIKeyEditor) {
            APIKeyEditor(apiKey: $openAIAPIKey)
        }
        .overlay {
            if showMaskPreview && selectionMode == .lasso && canvasTab == .ai {
                MaskPreviewOverlay(
                    points: selectionPoints,
                    onDismiss: { showMaskPreview = false },
                    onRedraw: {
                        showMaskPreview = false
                        startRedraw()
                    }
                )
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                ToastView(message: toastMessage) {
                    hideToast()
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastMessage)
    }

    private var currentTool: PKTool {
        switch selectedTool {
        case .ink:
            return PKInkingTool(selectedInk.inkType, color: selectedColor, width: selectedWidth)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }

    private var titleText: String {
        guard let entry = store.entry(for: entryID) else { return "Doodle" }
        return Self.dateFormatter.string(from: entry.createdAt)
    }

    private var backgroundImage: UIImage? {
        guard let data = store.entry(for: entryID)?.backgroundImageData else { return nil }
        return UIImage(data: data)
    }

    private var hasSelection: Bool {
        switch selectionMode {
        case .fullCanvas:
            return canvasSize.width > 0 && canvasSize.height > 0
        case .lasso:
            return selectionPoints.count > 2
        }
    }

    private func requestGenerate() {
        if selectionMode == .lasso && !hasSelection {
            presentToast("Draw a selection with the lasso first.")
            return
        }

        let prompt = buildPrompt()
        generateWithOpenAI(prompt: prompt)
    }

    private func generateWithOpenAI(prompt: String) {
        guard !isGenerating else { return }

        let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            showAPIKeyEditor = true
            return
        }

        guard let baseImage = renderCanvasImage() else {
            presentToast("Draw something on the canvas first.")
            return
        }

        let inputImage = renderLineArtImage() ?? baseImage

        guard let selectionCrop = renderSelectionCrop(from: inputImage),
              let inputData = selectionCrop.image.pngData() else {
            presentToast(selectionMode == .lasso ? "Draw a selection with the lasso first." : "Canvas isn't ready yet.")
            return
        }

        isGenerating = true

        Task {
            do {
                let service = OpenAIImageService(apiKey: trimmedKey)
                let requestSize = preferredImageSize(for: selectionCrop.rect)
                let generatedData = try await service.editImage(
                    imageData: inputData,
                    maskData: nil,
                    prompt: prompt,
                    size: requestSize
                )
                await MainActor.run {
                    let outputData: Data
                    if selectionMode == .fullCanvas {
                        outputData = generatedData
                    } else {
                        let composedData = composeGeneratedImage(
                            baseImage: baseImage,
                            generatedData: generatedData,
                            cropRect: selectionCrop.rect
                        )
                        outputData = composedData ?? generatedData
                    }
                    store.updateBackgroundImageData(outputData, for: entryID)
                    drawing = PKDrawing()
                    store.saveDrawing(drawing, for: entryID, generateThumbnail: true)
                    selectionActive = false
                    showMaskPreview = false
                    if selectionMode == .lasso {
                        clearSelection()
                    }
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    canvasLogger.error("Image generation failed: \(error.localizedDescription)")
                    presentToast(error.localizedDescription)
                    isGenerating = false
                }
            }
        }
    }

    private func renderCanvasImage() -> UIImage? {
        let hasDrawing = !drawing.bounds.isNull
        let hasBackground = backgroundImage != nil
        guard hasDrawing || hasBackground else { return nil }
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let rect = CGRect(origin: .zero, size: canvasSize)
        let drawingImage = drawing.image(from: rect, scale: UIScreen.main.scale)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)

            if let backgroundImage {
                backgroundImage.draw(in: rect)
            }
            drawingImage.draw(in: rect)
        }

        return image
    }

    private func renderLineArtImage() -> UIImage? {
        guard !drawing.bounds.isNull else { return nil }
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let rect = CGRect(origin: .zero, size: canvasSize)
        let drawingImage = drawing.image(from: rect, scale: UIScreen.main.scale)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)
            drawingImage.draw(in: rect)
        }

        return image
    }

    private func renderSelectionCrop(from baseImage: UIImage) -> SelectionCrop? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        if selectionMode == .fullCanvas {
            let rect = CGRect(origin: .zero, size: canvasSize)
            return SelectionCrop(image: baseImage, rect: rect)
        }
        guard hasSelection else { return nil }
        let lassoPath = selectionBezierPath(expandedBy: selectionExpansion)
        guard let rect = selectionBoundingRect(from: lassoPath, padding: 2) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = baseImage.scale

        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))

            let translatedPath = UIBezierPath(cgPath: lassoPath.cgPath)
            translatedPath.apply(CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
            context.cgContext.addPath(translatedPath.cgPath)
            context.cgContext.clip()

            let drawRect = CGRect(
                x: -rect.origin.x,
                y: -rect.origin.y,
                width: baseImage.size.width,
                height: baseImage.size.height
            )
            baseImage.draw(in: drawRect)
        }

        return SelectionCrop(image: image, rect: rect)
    }

    private func selectionBoundingRect(from path: UIBezierPath, padding: CGFloat) -> CGRect? {
        guard !path.isEmpty else { return nil }
        var rect = path.bounds.insetBy(dx: -padding, dy: -padding)
        let bounds = CGRect(origin: .zero, size: canvasSize)
        rect = rect.intersection(bounds)
        return rect.isNull ? nil : rect
    }

    private func selectionBezierPath(expandedBy padding: CGFloat = 0) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = selectionPoints.first else { return path }
        path.move(to: first)
        for point in selectionPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.close()
        guard padding > 0 else { return path }
        let strokedPath = path.cgPath.copy(
            strokingWithWidth: padding * 2,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )
        let expandedPath = UIBezierPath(cgPath: strokedPath)
        expandedPath.append(path)
        return expandedPath
    }

    private func composeGeneratedImage(baseImage: UIImage, generatedData: Data, cropRect: CGRect) -> Data? {
        guard let generatedImage = UIImage(data: generatedData) else { return nil }
        let rect = CGRect(origin: .zero, size: canvasSize)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)
            baseImage.draw(in: rect)

            let path = selectionBezierPath(expandedBy: selectionExpansion)
            guard !path.isEmpty else { return }
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()

            UIColor.white.setFill()
            context.fill(cropRect)

            let drawRect = aspectFillRect(for: generatedImage.size, in: cropRect)
            generatedImage.draw(in: drawRect)
        }
        return image.pngData()
    }

    private func clearSelection() {
        selectionPoints.removeAll()
        selectionClosed = false
    }

    private func startRedraw() {
        clearSelection()
        selectionActive = true
    }

    private func buildPrompt() -> String {
        "\(generationPrompt)\nStyle: \(selectedStyle.prompt)"
    }

    private func preferredImageSize(for rect: CGRect) -> String {
        guard rect.width > 0, rect.height > 0 else { return "1024x1024" }
        let ratio = rect.width / rect.height
        if ratio > 1.2 {
            return "1536x1024"
        }
        if ratio < 0.83 {
            return "1024x1536"
        }
        return "1024x1024"
    }

    private func aspectFillRect(for imageSize: CGSize, in targetRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetRect }
        let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: targetRect.midX - scaledSize.width / 2,
            y: targetRect.midY - scaledSize.height / 2
        )
        return CGRect(origin: origin, size: scaledSize)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @MainActor
    private func presentToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    @MainActor
    private func hideToast() {
        toastTask?.cancel()
        toastMessage = nil
    }
}

private enum CanvasTab: String, CaseIterable, Identifiable {
    case draw = "Draw"
    case ai = "AI"

    var id: String { rawValue }
}

private enum SelectionMode: String, CaseIterable, Identifiable {
    case fullCanvas = "Full Canvas"
    case lasso = "Lasso"

    var id: String { rawValue }
}

private enum ToolKind: String, CaseIterable, Identifiable {
    case ink = "Ink"
    case eraser = "Eraser"

    var id: String { rawValue }
}

private enum InkStyle: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case marker = "Marker"

    var id: String { rawValue }

    var inkType: PKInk.InkType {
        switch self {
        case .pen:
            return .pen
        case .marker:
            return .marker
        }
    }
}

private enum GenerationStyle: String, CaseIterable, Identifiable {
    case cute = "Cute"
    case ghibli = "Ghibli"
    case marvel = "Marvel"

    var id: String { rawValue }

    var prompt: String {
        switch self {
        case .cute:
            return "Cute pastel illustration with soft shading and playful details."
        case .ghibli:
            return "Ghibli-inspired hand-painted anime style with warm lighting and gentle textures."
        case .marvel:
            return "Marvel-inspired comic book style with bold inks, dynamic lighting, and vibrant colors."
        }
    }
}

private struct SelectionCrop {
    let image: UIImage
    let rect: CGRect
}

private struct CanvasControls: View {
    @Binding var canvasTab: CanvasTab
    @Binding var selectedTool: ToolKind
    @Binding var selectedInk: InkStyle
    @Binding var selectedColor: UIColor
    @Binding var selectedWidth: CGFloat
    @Binding var selectionMode: SelectionMode
    @Binding var selectionActive: Bool
    @Binding var selectedStyle: GenerationStyle
    let hasSelection: Bool
    let isGenerating: Bool
    let onGenerate: () -> Void
    let onClearSelection: () -> Void
    let onPreviewSelection: () -> Void
    let onRedrawSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Mode", selection: $canvasTab) {
                ForEach(CanvasTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if canvasTab == .draw {
                DrawControls(
                    selectedTool: $selectedTool,
                    selectedInk: $selectedInk,
                    selectedColor: $selectedColor,
                    selectedWidth: $selectedWidth
                )
            } else {
                AIControls(
                    selectionMode: $selectionMode,
                    selectionActive: $selectionActive,
                    selectedStyle: $selectedStyle,
                    hasSelection: hasSelection,
                    isGenerating: isGenerating,
                    onGenerate: onGenerate,
                    onClearSelection: onClearSelection,
                    onPreviewSelection: onPreviewSelection,
                    onRedrawSelection: onRedrawSelection
                )
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct DrawControls: View {
    @Binding var selectedTool: ToolKind
    @Binding var selectedInk: InkStyle
    @Binding var selectedColor: UIColor
    @Binding var selectedWidth: CGFloat
    @State private var showInkMenu = false

    private let palette: [UIColor] = [
        .black,
        .systemBlue,
        .systemRed,
        .systemGreen,
        .systemOrange,
        .systemPurple,
        .systemYellow,
        .systemBrown
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ToolIconButton(
                    systemImage: "pencil.tip",
                    isSelected: selectedTool == .ink
                ) {
                    selectedTool = .ink
                }

                ToolIconButton(
                    systemImage: "eraser",
                    isSelected: selectedTool == .eraser
                ) {
                    selectedTool = .eraser
                }

                Spacer()

                if selectedTool == .ink {
                    Button {
                        showInkMenu = true
                    } label: {
                        CompactCapsuleLabel(text: selectedInk.rawValue)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Ink Style",
                        isPresented: $showInkMenu,
                        titleVisibility: .visible
                    ) {
                        ForEach(InkStyle.allCases) { style in
                            Button(style.rawValue) {
                                selectedInk = style
                            }
                        }
                    }
                }
            }

            if selectedTool == .ink {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(palette.indices, id: \.self) { index in
                                let color = palette[index]
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(Color(uiColor: color))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isSelected(color) ? Color.primary : Color.clear,
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(colorName(for: color)))
                            }
                        }
                    }

                    Slider(value: $selectedWidth, in: 2...24, step: 1)
                        .frame(height: 18)

                    Circle()
                        .fill(Color(uiColor: selectedColor))
                        .frame(
                            width: min(14, max(6, selectedWidth * 0.5)),
                            height: min(14, max(6, selectedWidth * 0.5))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                }
            } else {
                Text("Erase by scrubbing the canvas.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func isSelected(_ color: UIColor) -> Bool {
        color.isEqual(selectedColor)
    }

    private func colorName(for color: UIColor) -> String {
        switch color {
        case UIColor.black:
            return "Black"
        case UIColor.systemBlue:
            return "Blue"
        case UIColor.systemRed:
            return "Red"
        case UIColor.systemGreen:
            return "Green"
        case UIColor.systemOrange:
            return "Orange"
        case UIColor.systemPurple:
            return "Purple"
        case UIColor.systemYellow:
            return "Yellow"
        case UIColor.systemBrown:
            return "Brown"
        default:
            return "Color"
        }
    }
}

private struct AIControls: View {
    @Binding var selectionMode: SelectionMode
    @Binding var selectionActive: Bool
    @Binding var selectedStyle: GenerationStyle
    let hasSelection: Bool
    let isGenerating: Bool
    let onGenerate: () -> Void
    let onClearSelection: () -> Void
    let onPreviewSelection: () -> Void
    let onRedrawSelection: () -> Void
    @State private var showStyleMenu = false
    @State private var showSelectionActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    showStyleMenu = true
                } label: {
                    CompactCapsuleLabel(text: selectedStyle.rawValue)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Generation Style",
                    isPresented: $showStyleMenu,
                    titleVisibility: .visible
                ) {
                    ForEach(GenerationStyle.allCases) { style in
                        Button(style.rawValue) {
                            selectedStyle = style
                        }
                    }
                }

                Spacer()

                Button(action: onGenerate) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(isGenerating || !hasSelection)
            }

            Picker("Selection", selection: $selectionMode) {
                ForEach(SelectionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if selectionMode == .lasso {
                HStack(spacing: 8) {
                    Button {
                        selectionActive.toggle()
                    } label: {
                        Image(systemName: selectionActive ? "stop.circle.fill" : "lasso")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if hasSelection {
                        Button {
                            showSelectionActions = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Selection actions")
                        .confirmationDialog(
                            "Selection",
                            isPresented: $showSelectionActions,
                            titleVisibility: .visible
                        ) {
                            Button("Preview") {
                                onPreviewSelection()
                            }

                            Button("Redraw") {
                                onRedrawSelection()
                            }

                            Button("Clear", role: .destructive) {
                                onClearSelection()
                            }
                        }
                    }

                    Text(selectionStatusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
            } else {
                Text(selectionStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var selectionStatusText: String {
        switch selectionMode {
        case .fullCanvas:
            return "Full canvas selected"
        case .lasso:
            if hasSelection {
                return "Selection ready"
            }
            if selectionActive {
                return "Drawing selection..."
            }
            return "No selection"
        }
    }
}

private struct ToolIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(systemImage))
    }
}

private struct CompactCapsuleLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

private struct ToastView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss error")
    }
}

private struct CaptionEditor: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isFocused ? 8 : 6) {
            Button {
                isFocused.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: isFocused ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isFocused ? "Collapse notes" : "Expand notes"))

            if isFocused {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 96, maxHeight: 160)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)

                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add a note or caption for this doodle.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 6)
                    }
                }
            } else {
                Text(previewText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isFocused ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isFocused = false
                }
            }
        }
    }

    private var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Tap to add a note or caption." : trimmed
    }
}

private struct LassoSelectionOverlay: View {
    @Binding var points: [CGPoint]
    @Binding var isActive: Bool
    @Binding var isClosed: Bool

    @State private var isDrawing = false

    var body: some View {
        ZStack {
            Color.clear

            if points.count > 1 {
                let path = selectionPath(closed: isClosed)
                path
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )

                if isClosed {
                    path
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(isActive)
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                isDrawing = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isActive else { return }
                    if !isDrawing {
                        isDrawing = true
                        points = [value.location]
                        isClosed = false
                    } else {
                        points.append(value.location)
                    }
                }
                .onEnded { _ in
                    guard isActive else { return }
                    isDrawing = false
                    isClosed = points.count > 2
                }
        )
    }

    private func selectionPath(closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }
}

private struct MaskPreviewOverlay: View {
    let points: [CGPoint]
    let onDismiss: () -> Void
    let onRedraw: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }

            if points.count > 2 {
                selectionPath
                    .fill(Color.black)
                    .blendMode(.destinationOut)

                selectionPath
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }

            VStack(alignment: .trailing, spacing: 8) {
                Button("Redraw") {
                    onRedraw()
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .compositingGroup()
    }

    private var selectionPath: Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct APIKeyEditor: View {
    @Binding var apiKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API Key") {
                    SecureField("sk-...", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Stored locally on this device. For production, use a backend.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("API Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        apiKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                draftKey = apiKey
            }
        }
    }
}
