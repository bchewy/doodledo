import PencilKit
import SwiftUI
import UIKit

struct CanvasView: View {
    @EnvironmentObject private var store: DoodleStore
    let entryID: UUID

    @State private var drawing = PKDrawing()
    @State private var caption = ""
    @State private var selectedTool = ToolKind.ink
    @State private var selectedInk = InkStyle.pen
    @State private var selectedColor: UIColor = .black
    @State private var selectedWidth: CGFloat = 6
    @AppStorage("openai_api_key") private var openAIAPIKey = ""
    @State private var isGenerating = false
    @State private var showAPIKeyEditor = false
    @State private var generationError: String?
    @State private var canvasSize: CGSize = .zero
    @State private var selectionPoints: [CGPoint] = []
    @State private var selectionActive = false
    @State private var selectionClosed = false
    @State private var showMaskPreview = false
    @State private var showPromptEditor = false
    @State private var promptText = ""

    private let generationPrompt = """
    Create a cute, playful illustration based on the provided doodle. Preserve the subject's shape and pose. Use clean lines, soft pastel colors, and a friendly, charming vibe. No text.
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

                if selectedTool == .lasso {
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
            .onChange(of: proxy.size) { newSize in
                canvasSize = newSize
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            ToolControls(
                selectedTool: $selectedTool,
                selectedInk: $selectedInk,
                selectedColor: $selectedColor,
                selectedWidth: $selectedWidth,
                selectionActive: $selectionActive,
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
        .onChange(of: caption) { newValue in
            store.updateCaption(newValue, for: entryID)
        }
        .onChange(of: selectionActive) { newValue in
            if !newValue {
                selectionClosed = selectionPoints.count > 2
            }
        }
        .onChange(of: selectedTool) { newValue in
            if newValue != .lasso {
                selectionActive = false
                showMaskPreview = false
                clearSelection()
            }
        }
        .onDisappear {
            store.saveDrawing(drawing, for: entryID, generateThumbnail: true)
        }
        .alert("Image Generation Failed", isPresented: Binding(
            get: { generationError != nil },
            set: { newValue in
                if !newValue {
                    generationError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(generationError ?? "Something went wrong.")
        }
        .sheet(isPresented: $showAPIKeyEditor) {
            APIKeyEditor(apiKey: $openAIAPIKey)
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditor(
                prompt: $promptText,
                onCancel: {},
                onGenerate: {
                    let prompt = buildPrompt()
                    showPromptEditor = false
                    generateWithOpenAI(prompt: prompt)
                }
            )
        }
        .overlay {
            if showMaskPreview {
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
    }

    private var currentTool: PKTool {
        switch selectedTool {
        case .ink:
            return PKInkingTool(selectedInk.inkType, color: selectedColor, width: selectedWidth)
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
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
        selectionPoints.count > 2
    }

    private func requestGenerate() {
        guard hasSelection else {
            generationError = "Draw a selection with the lasso first."
            return
        }

        if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        showPromptEditor = true
    }

    private func generateWithOpenAI(prompt: String) {
        guard !isGenerating else { return }

        let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            showAPIKeyEditor = true
            return
        }

        guard let inputImageData = renderSelectionImageData() else {
            generationError = "Draw something inside the selection."
            return
        }

        isGenerating = true

        Task {
            do {
                let service = OpenAIImageService(apiKey: trimmedKey)
                let generatedData = try await service.editImage(
                    imageData: inputImageData,
                    maskData: nil,
                    prompt: prompt
                )
                await MainActor.run {
                    store.updateBackgroundImageData(generatedData, for: entryID)
                    drawing = PKDrawing()
                    store.saveDrawing(drawing, for: entryID, generateThumbnail: true)
                    selectionActive = false
                    clearSelection()
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func renderSelectionImageData() -> Data? {
        let hasDrawing = !drawing.bounds.isNull
        let hasBackground = backgroundImage != nil
        guard hasSelection, (hasDrawing || hasBackground) else { return nil }
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let rect = CGRect(origin: .zero, size: canvasSize)
        let drawingImage = drawing.image(from: rect, scale: UIScreen.main.scale)

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)

            let path = UIBezierPath()
            path.move(to: selectionPoints[0])
            for point in selectionPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.close()
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()

            if let backgroundImage {
                backgroundImage.draw(in: rect)
            }
            drawingImage.draw(in: rect)
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
        let userPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if userPrompt.isEmpty {
            return generationPrompt
        }
        return "\(generationPrompt)\n\nUser prompt: \(userPrompt)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private enum ToolKind: String, CaseIterable, Identifiable {
    case ink = "Ink"
    case eraser = "Eraser"
    case lasso = "Lasso"

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

private struct ToolControls: View {
    @Binding var selectedTool: ToolKind
    @Binding var selectedInk: InkStyle
    @Binding var selectedColor: UIColor
    @Binding var selectedWidth: CGFloat
    @Binding var selectionActive: Bool
    let hasSelection: Bool
    let isGenerating: Bool
    let onGenerate: () -> Void
    let onClearSelection: () -> Void
    let onPreviewSelection: () -> Void
    let onRedrawSelection: () -> Void

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
    private let lassoActionColumns = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tool", selection: $selectedTool) {
                ForEach(ToolKind.allCases) { tool in
                    Text(tool.rawValue).tag(tool)
                }
            }
            .pickerStyle(.segmented)

            if selectedTool == .ink {
                Picker("Tool", selection: $selectedInk) {
                    ForEach(InkStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    ForEach(palette.indices, id: \.self) { index in
                        let color = palette[index]
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(uiColor: color))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isSelected(color) ? Color.primary : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(colorName(for: color)))
                    }
                }

                HStack(spacing: 12) {
                    Text("Size")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: $selectedWidth, in: 2...24, step: 1)

                    Circle()
                        .fill(Color(uiColor: selectedColor))
                        .frame(width: max(10, selectedWidth), height: max(10, selectedWidth))
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                }
            } else if selectedTool == .lasso {
                Text("Use the AI lasso to target the area to regenerate.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    selectionActive.toggle()
                } label: {
                    LassoActionLabel(
                        title: selectionActive ? "Stop" : "Draw",
                        systemImage: selectionActive ? "stop.circle.fill" : "lasso"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if hasSelection {
                    LazyVGrid(columns: lassoActionColumns, alignment: .leading, spacing: 8) {
                        Button {
                            onPreviewSelection()
                        } label: {
                            LassoActionLabel(title: "Preview", systemImage: "eye")
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            onRedrawSelection()
                        } label: {
                            LassoActionLabel(title: "Redraw", systemImage: "arrow.clockwise")
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            onClearSelection()
                        } label: {
                            LassoActionLabel(title: "Clear", systemImage: "xmark")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(selectionStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: onGenerate) {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Generate with GPT-Image-1.5")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || !hasSelection)
            } else {
                Text("Erase by scrubbing the canvas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
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

    private var selectionStatusText: String {
        if hasSelection {
            return "Selection ready"
        }
        if selectionActive {
            return "Drawing selection..."
        }
        return "No selection"
    }
}

private struct LassoActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
        .onChange(of: isActive) { newValue in
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

private struct PromptEditor: View {
    @Binding var prompt: String
    let onCancel: () -> Void
    let onGenerate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a prompt to guide the generation.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)

                    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("e.g. cute bunny, pastel colors, cozy vibe")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 6)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .padding(16)
            .navigationTitle("Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        onGenerate()
                        dismiss()
                    }
                }
            }
        }
    }
}
