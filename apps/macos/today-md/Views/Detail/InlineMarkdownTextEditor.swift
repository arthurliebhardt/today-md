import AppKit
import SwiftUI

@MainActor
struct InlineMarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextViewReady: (NSTextView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextViewReady: onTextViewReady)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = InlineMarkdownNSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 220)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.focusRingType = NSFocusRingType.none
        textView.onInsertNewlineCommand = { [weak coordinator = context.coordinator] textView in
            coordinator?.handleInsertNewline(from: textView) ?? false
        }
        textView.onCheckboxToggle = { [weak coordinator = context.coordinator] offset in
            coordinator?.toggleCheckbox(at: offset)
        }

        scrollView.documentView = textView
        context.coordinator.attach(textView)
        context.coordinator.applyTextIfNeeded(text, force: true)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onTextViewReady = onTextViewReady
        context.coordinator.applyTextIfNeeded(text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var onTextViewReady: (NSTextView) -> Void
        weak var textView: NSTextView?
        private var isApplyingProgrammaticUpdate = false
        private var lastTextSnapshot = ""

        init(text: Binding<String>, onTextViewReady: @escaping (NSTextView) -> Void) {
            self.text = text
            self.onTextViewReady = onTextViewReady
        }

        func attach(_ textView: NSTextView) {
            self.textView = textView
            lastTextSnapshot = textView.string
            onTextViewReady(textView)
        }

        func applyTextIfNeeded(_ text: String, force: Bool = false) {
            guard let textView else { return }
            onTextViewReady(textView)

            guard force || textView.string != text else {
                applyStyling(to: textView, preservingSelection: textView.selectedRange())
                return
            }

            applyText(text, to: textView, preservingSelection: textView.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingProgrammaticUpdate else { return }

            let previousText = lastTextSnapshot
            let currentText = textView.string
            let selection = textView.selectedRange()

            if selection.length == 0,
               let edit = MarkdownInlineDisplay.editForAutoContinuation(
                oldDisplay: previousText,
                newDisplay: currentText
               ) {
                applyText(
                    edit.text,
                    to: textView,
                    preservingSelection: NSRange(location: edit.cursorLocation, length: 0)
                )
                text.wrappedValue = edit.text
                return
            }

            applyStyling(to: textView, preservingSelection: selection)
            text.wrappedValue = textView.string
        }

        func handleInsertNewline(from textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let original = textView.string
            let newText = (original as NSString).replacingCharacters(in: selection, with: "\n")

            guard let edit = MarkdownInlineDisplay.editForAutoContinuation(oldDisplay: original, newDisplay: newText) else {
                return false
            }

            applyText(
                edit.text,
                to: textView,
                preservingSelection: NSRange(location: edit.cursorLocation, length: 0)
            )
            text.wrappedValue = edit.text
            return true
        }

        func toggleCheckbox(at offset: Int) {
            guard let textView,
                  let toggled = MarkdownInlineDisplay.toggledCheckbox(in: textView.string, atEditorOffset: offset) else {
                return
            }

            let selection = textView.selectedRange()
            applyText(toggled, to: textView, preservingSelection: selection)
            text.wrappedValue = toggled
        }

        private func applyText(_ text: String, to textView: NSTextView, preservingSelection selection: NSRange) {
            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(InlineMarkdownEditorStyle.attributedText(for: text))
            textView.setSelectedRange(clamped(selection, in: text))
            textView.setNeedsDisplay(textView.bounds)
            lastTextSnapshot = text
            isApplyingProgrammaticUpdate = false
        }

        private func applyStyling(to textView: NSTextView, preservingSelection selection: NSRange) {
            isApplyingProgrammaticUpdate = true
            let rawText = textView.string
            textView.textStorage?.setAttributedString(InlineMarkdownEditorStyle.attributedText(for: rawText))
            textView.setSelectedRange(clamped(selection, in: rawText))
            textView.setNeedsDisplay(textView.bounds)
            lastTextSnapshot = rawText
            isApplyingProgrammaticUpdate = false
        }

        private func clamped(_ range: NSRange, in text: String) -> NSRange {
            let length = (text as NSString).length
            let location = min(max(range.location, 0), length)
            let end = min(max(range.location + range.length, 0), length)
            let clampedRange = NSRange(location: location, length: max(end - location, 0))
            return InlineMarkdownEditorStyle.selectionAvoidingHiddenCodeFence(clampedRange, in: text)
        }
    }
}

final class InlineMarkdownNSTextView: NSTextView {
    var onInsertNewlineCommand: ((InlineMarkdownNSTextView) -> Bool)?
    var onCheckboxToggle: ((Int) -> Void)?

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(InlineMarkdownEditorStyle.selectionAvoidingHiddenCodeFence(charRange, in: string))
        setNeedsDisplay(bounds)
    }

    override func setSelectedRange(
        _ charRange: NSRange,
        affinity: NSSelectionAffinity,
        stillSelecting flag: Bool
    ) {
        super.setSelectedRange(
            InlineMarkdownEditorStyle.selectionAvoidingHiddenCodeFence(charRange, in: string),
            affinity: affinity,
            stillSelecting: flag
        )
        setNeedsDisplay(bounds)
    }

    override func keyDown(with event: NSEvent) {
        let relevantFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76),
           relevantFlags.isSubset(of: [.shift]),
           onInsertNewlineCommand?(self) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if onInsertNewlineCommand?(self) == true {
            return
        }
        super.insertNewline(sender)
    }

    override func insertLineBreak(_ sender: Any?) {
        if onInsertNewlineCommand?(self) == true {
            return
        }
        super.insertLineBreak(sender)
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        if onInsertNewlineCommand?(self) == true {
            return
        }
        super.insertNewlineIgnoringFieldEditor(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
        drawDividerMarkers(in: dirtyRect)
        drawChecklistMarkers(in: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        guard let characterIndex = characterIndex(at: event.locationInWindow),
              let markerRange = MarkdownInlineDisplay.checkboxMarkerRange(in: string, atEditorOffset: characterIndex),
              let markerRect = checkboxRect(for: markerRange) else {
            super.mouseDown(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        if markerRect.contains(localPoint) {
            onCheckboxToggle?(characterIndex)
            return
        }

        super.mouseDown(with: event)
    }

    private func characterIndex(at windowPoint: NSPoint) -> Int? {
        guard let textContainer, let layoutManager else { return nil }

        let localPoint = convert(windowPoint, from: nil)
        let containerPoint = NSPoint(
            x: localPoint.x - textContainerInset.width,
            y: localPoint.y - textContainerInset.height
        )

        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    private func checkboxRect(for markerRange: NSRange) -> NSRect? {
        guard let textContainer, let layoutManager else { return nil }

        let tokenRange = NSRange(location: markerRange.location, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: tokenRange, actualCharacterRange: nil)
        var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        glyphRect.origin.x += textContainerInset.width
        glyphRect.origin.y += textContainerInset.height

        let side = max(min(glyphRect.height - 1, 14), 12)
        return NSRect(
            x: glyphRect.minX + 1,
            y: glyphRect.midY - side / 2,
            width: side,
            height: side
        ).insetBy(dx: -2, dy: -2)
    }

    private func drawChecklistMarkers(in dirtyRect: NSRect) {
        let nsText = string as NSString
        guard nsText.length > 0 else { return }

        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange)

            if let token = MarkdownInlineDisplay.leadingToken(in: line),
               token.token == .uncheckedChecklist || token.token == .checkedChecklist {
                let tokenRange = NSRange(location: lineRange.location + token.range.location, length: token.range.length)
                if let rect = checkboxRect(for: tokenRange), rect.intersects(dirtyRect) {
                    drawChecklistMarker(in: rect, checked: token.token == .checkedChecklist)
                }
            }

            location = NSMaxRange(lineRange)
        }
    }

    private func drawDividerMarkers(in dirtyRect: NSRect) {
        let nsText = string as NSString
        guard nsText.length > 0 else { return }

        var location = 0
        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentRange(for: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)

            if contentRange.length != lineRange.length,
               MarkdownInlineDisplay.isDividerMarkdownLine(line),
               let rect = dividerRect(for: contentRange),
               rect.intersects(dirtyRect) {
                drawDividerMarker(in: rect)
            }

            location = NSMaxRange(lineRange)
        }
    }

    private func dividerRect(for characterRange: NSRange) -> NSRect? {
        guard let layoutManager, characterRange.length > 0 else { return nil }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }

        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    private func drawDividerMarker(in rect: NSRect) {
        let horizontalInset = textContainerInset.width + 4
        let width = max(bounds.width - (horizontalInset * 2), 0)
        let lineHeight: CGFloat = 1
        let dividerRect = NSRect(
            x: horizontalInset,
            y: rect.midY - (lineHeight / 2),
            width: width,
            height: lineHeight
        )

        let path = NSBezierPath(roundedRect: dividerRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        NSColor.separatorColor.withAlphaComponent(0.28).setFill()
        path.fill()
    }

    private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        let nsText = string as NSString
        guard nsText.length > 0, let layoutManager, let textContainer else { return }

        var location = 0
        var inCodeBlock = false
        var blockCharRange: NSRange?

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentRange(for: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock, let charRange = blockCharRange {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                    if glyphRange.length > 0 {
                        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        rect.origin.x += textContainerInset.width
                        rect.origin.y += textContainerInset.height
                        if rect.intersects(dirtyRect) {
                            drawCodeBlockBackground(in: rect)
                        }
                    }
                    blockCharRange = nil
                }
                inCodeBlock.toggle()
                location = NSMaxRange(lineRange)
                continue
            }

            if inCodeBlock {
                if let existing = blockCharRange {
                    blockCharRange = NSUnionRange(existing, lineRange)
                } else {
                    blockCharRange = lineRange
                }
            }

            location = NSMaxRange(lineRange)
        }

        if inCodeBlock, let charRange = blockCharRange {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            if glyphRange.length > 0 {
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                rect.origin.x += textContainerInset.width
                rect.origin.y += textContainerInset.height
                if rect.intersects(dirtyRect) {
                    drawCodeBlockBackground(in: rect)
                }
            }
        }
    }

    private func drawCodeBlockBackground(in rect: NSRect) {
        let horizontalInset = max(textContainerInset.width - 4, 8)
        let width = max(bounds.width - (horizontalInset * 2), 0)
        let backgroundRect = NSRect(
            x: horizontalInset,
            y: rect.minY - 4,
            width: width,
            height: rect.height + 8
        )

        let cornerRadius = min(backgroundRect.height * 0.12, 10)
        let path = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
        codeBlockFillColor().setFill()
        path.fill()
    }

    private func codeBlockFillColor() -> NSColor {
        let bg = NSColor.controlBackgroundColor.usingColorSpace(.sRGB)
            ?? NSColor.controlBackgroundColor
        let label = NSColor.secondaryLabelColor.usingColorSpace(.sRGB)
            ?? NSColor.secondaryLabelColor
        let r = bg.redComponent + (label.redComponent - bg.redComponent) * 0.12 * label.alphaComponent
        let g = bg.greenComponent + (label.greenComponent - bg.greenComponent) * 0.12 * label.alphaComponent
        let b = bg.blueComponent + (label.blueComponent - bg.blueComponent) * 0.12 * label.alphaComponent
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    private func drawChecklistMarker(in rect: NSRect, checked: Bool) {
        let boxRect = rect.insetBy(dx: 2, dy: 2)
        let cornerRadius = boxRect.width * 0.28
        let strokeColor = checked ? NSColor.systemGreen : NSColor.systemRed

        let path = NSBezierPath(roundedRect: boxRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = 1.55

        if checked {
            strokeColor.setFill()
            path.fill()
            NSColor.white.setStroke()

            let check = NSBezierPath()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: boxRect.minX + boxRect.width * 0.24, y: boxRect.midY - 0.5))
            check.line(to: NSPoint(x: boxRect.minX + boxRect.width * 0.44, y: boxRect.minY + boxRect.height * 0.26))
            check.line(to: NSPoint(x: boxRect.maxX - boxRect.width * 0.18, y: boxRect.maxY - boxRect.height * 0.26))
            check.stroke()
        } else {
            strokeColor.setStroke()
            path.stroke()
        }
    }
}

@MainActor
private enum InlineMarkdownEditorStyle {
    static func attributedText(for text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes()
        )

        let nsText = text as NSString
        var protectedRanges: [NSRange] = []
        var inCodeBlock = false
        var previousLineClosedCodeBlock = false
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = lineContentRange(for: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)
            let needsSpacingAfterCodeBlock = previousLineClosedCodeBlock
            previousLineClosedCodeBlock = false

            if isCodeFence(line) {
                let isClosingFence = inCodeBlock
                collapseCodeFenceLine(lineRange, isClosingFence: isClosingFence, in: attributed)
                inCodeBlock.toggle()
                previousLineClosedCodeBlock = isClosingFence
                location = NSMaxRange(lineRange)
                continue
            }

            if inCodeBlock {
                attributed.addAttributes(codeBlockAttributes(), range: lineRange)
                attributed.addAttribute(.paragraphStyle, value: codeParagraphStyle(), range: lineRange)
                protectedRanges.append(lineRange)
                location = NSMaxRange(lineRange)
                continue
            }

            if contentRange.length != lineRange.length,
               MarkdownInlineDisplay.isDividerMarkdownLine(line) {
                styleDividerLine(contentRange: contentRange, lineRange: lineRange, in: attributed)
                location = NSMaxRange(lineRange)
                continue
            }

            if let heading = headingInfo(for: line) {
                hideMarkdownRange(offset(heading.markerRange, by: contentRange.location), in: attributed)
                let headingContentRange = offset(heading.contentRange, by: contentRange.location)
                if headingContentRange.length > 0 {
                    attributed.addAttributes(headingAttributes(level: heading.level), range: headingContentRange)
                }
                attributed.addAttribute(.paragraphStyle, value: headingParagraphStyle(level: heading.level), range: lineRange)
            }

            if let numbered = numberedListInfo(for: line) {
                attributed.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: NSColor.systemRed
                    ],
                    range: offset(numbered.markerRange, by: contentRange.location)
                )
            }

            if let token = MarkdownInlineDisplay.leadingToken(in: line) {
                styleLeadingToken(token, lineContentRange: contentRange, in: attributed)
            }

            if needsSpacingAfterCodeBlock {
                addSpacingBeforeParagraph(in: lineRange, amount: 14, to: attributed)
            }

            location = NSMaxRange(lineRange)
        }

        applyInlineMarkdownStyles(to: attributed, text: text, protectedRanges: protectedRanges)

        return attributed
    }

    static func selectionAvoidingHiddenCodeFence(_ range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        let length = nsText.length
        let location = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, 0), length)
        let clampedRange = NSRange(location: location, length: max(end - location, 0))

        guard clampedRange.length == 0 else {
            return clampedRange
        }

        var adjustedLocation = clampedRange.location

        while adjustedLocation < length {
            let lineRange = nsText.lineRange(for: NSRange(location: adjustedLocation, length: 0))
            guard adjustedLocation < NSMaxRange(lineRange) else { break }

            let contentRange = lineContentRange(for: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)

            guard isCodeFence(line) else { break }

            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > adjustedLocation else { break }
            adjustedLocation = nextLocation
        }

        return NSRange(location: adjustedLocation, length: 0)
    }

    private static func applyInlineMarkdownStyles(
        to attributed: NSMutableAttributedString,
        text: String,
        protectedRanges: [NSRange]
    ) {
        var consumedRanges = protectedRanges

        applyPattern(#"`([^`\n]+)`"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            if contentRange.length > 0 {
                attributed.addAttributes(codeSpanAttributes(), range: contentRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 1), in: attributed)
            hideMarkdownRange(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: attributed)
        }

        applyPattern(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 3 else { return }
            let labelRange = match.range(at: 1)
            if labelRange.length > 0 {
                attributed.addAttributes(linkAttributes(), range: labelRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 1), in: attributed)
            hideMarkdownRange(
                NSRange(location: NSMaxRange(labelRange), length: NSMaxRange(match.range) - NSMaxRange(labelRange)),
                in: attributed
            )
        }

        applyPattern(#"\*\*([^\n]+?)\*\*"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            if contentRange.length > 0 {
                attributed.addAttributes(boldAttributes(), range: contentRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 2), in: attributed)
            hideMarkdownRange(NSRange(location: NSMaxRange(match.range) - 2, length: 2), in: attributed)
        }

        applyPattern(#"~~([^\n]+?)~~"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            if contentRange.length > 0 {
                attributed.addAttributes(strikethroughAttributes(), range: contentRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 2), in: attributed)
            hideMarkdownRange(NSRange(location: NSMaxRange(match.range) - 2, length: 2), in: attributed)
        }

        applyPattern(#"_([^\n_]+?)_"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            if contentRange.length > 0 {
                attributed.addAttributes(italicAttributes(), range: contentRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 1), in: attributed)
            hideMarkdownRange(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: attributed)
        }

        applyPattern(#"(?<!\*)\*([^\n*]+?)\*(?!\*)"#, to: attributed, in: text, consumedRanges: &consumedRanges) { match in
            guard match.numberOfRanges >= 2 else { return }
            let contentRange = match.range(at: 1)
            if contentRange.length > 0 {
                attributed.addAttributes(italicAttributes(), range: contentRange)
            }
            hideMarkdownRange(NSRange(location: match.range.location, length: 1), in: attributed)
            hideMarkdownRange(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: attributed)
        }
    }

    private static func applyPattern(
        _ pattern: String,
        to attributed: NSMutableAttributedString,
        in text: String,
        consumedRanges: inout [NSRange],
        applier: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            guard !consumedRanges.contains(where: { $0.intersection(match.range) != nil }) else { continue }
            applier(match)
            consumedRanges.append(match.range)
        }
    }

    private static func styleLeadingToken(
        _ token: (token: MarkdownInlineDisplay.LeadingToken, range: NSRange),
        lineContentRange: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        let tokenRange = NSRange(
            location: lineContentRange.location + token.range.location,
            length: 1
        )

        if token.token == .bullet {
            attributed.addAttributes(
                [
                    .font: tokenFont(for: token.token),
                    .foregroundColor: tokenColor(for: token.token)
                ],
                range: tokenRange
            )
        } else {
            attributed.addAttributes(
                [
                    .font: tokenFont(for: token.token),
                    .foregroundColor: NSColor.clear,
                    .kern: 4.5
                ],
                range: tokenRange
            )
        }

        if token.token == .checkedChecklist {
            let trailingRange = NSRange(
                location: lineContentRange.location + token.range.location + token.range.length,
                length: max(lineContentRange.length - token.range.location - token.range.length, 0)
            )

            if trailingRange.length > 0 {
                attributed.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: trailingRange
                )
            }
        }
    }

    private static func styleDividerLine(
        contentRange: NSRange,
        lineRange: NSRange,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(dividerContentAttributes(), range: contentRange)
        attributed.addAttribute(.paragraphStyle, value: dividerParagraphStyle(), range: lineRange)
    }

    private static func headingInfo(for line: String) -> (level: Int, markerRange: NSRange, contentRange: NSRange)? {
        let nsLine = line as NSString
        var index = 0

        while index < nsLine.length {
            let scalar = nsLine.character(at: index)
            if scalar == 32 || scalar == 9 {
                index += 1
            } else {
                break
            }
        }

        let markerStart = index
        var level = 0

        while index < nsLine.length, nsLine.character(at: index) == 35, level < 4 {
            level += 1
            index += 1
        }

        guard (1...3).contains(level), index < nsLine.length, nsLine.character(at: index) == 32 else {
            return nil
        }

        index += 1
        return (
            level,
            NSRange(location: markerStart, length: index - markerStart),
            NSRange(location: index, length: nsLine.length - index)
        )
    }

    private static func numberedListInfo(for line: String) -> (markerRange: NSRange, contentRange: NSRange)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(\d+\.)\s+"#) else { return nil }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        guard let match = regex.firstMatch(in: line, range: fullRange), match.numberOfRanges >= 3 else {
            return nil
        }

        let markerRange = match.range(at: 2)
        return (
            markerRange,
            NSRange(location: NSMaxRange(match.range), length: nsLine.length - NSMaxRange(match.range))
        )
    }

    private static func isCodeFence(_ line: String) -> Bool {
        isCodeFenceLine(line)
    }

    private static func collapseCodeFenceLine(
        _ lineRange: NSRange,
        isClosingFence: Bool,
        in attributed: NSMutableAttributedString
    ) {
        attributed.addAttributes(codeFenceLineAttributes(isClosingFence: isClosingFence), range: lineRange)
    }

    private static func hideMarkdownRange(_ range: NSRange, in attributed: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        attributed.addAttributes(hiddenMarkdownAttributes(), range: range)
    }

    private static func lineContentRange(for lineRange: NSRange, in text: NSString) -> NSRange {
        var contentRange = lineRange

        while contentRange.length > 0 {
            let lastCharacter = text.character(at: NSMaxRange(contentRange) - 1)
            if lastCharacter == 10 || lastCharacter == 13 {
                contentRange.length -= 1
            } else {
                break
            }
        }

        return contentRange
    }

    private static func offset(_ range: NSRange, by amount: Int) -> NSRange {
        NSRange(location: range.location + amount, length: range.length)
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private static func boldAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private static func italicAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private static func strikethroughAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func codeSpanAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 12.75, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.controlBackgroundColor
        ]
    }

    private static func linkAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.labelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let font: NSFont

        switch level {
        case 1:
            font = NSFont.systemFont(ofSize: 22, weight: .bold)
        case 2:
            font = NSFont.systemFont(ofSize: 18, weight: .bold)
        default:
            font = NSFont.systemFont(ofSize: 15.5, weight: .semibold)
        }

        return [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
    }

    private static func codeBlockAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: codeBlockFont(),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.72)
        ]
    }

    private static func codeBlockFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 12.75, weight: .regular)
    }

    private static func tokenFont(for token: MarkdownInlineDisplay.LeadingToken) -> NSFont {
        switch token {
        case .uncheckedChecklist, .checkedChecklist:
            return NSFont.systemFont(ofSize: 15.5, weight: .medium)
        case .bullet:
            return NSFont.systemFont(ofSize: 14.5, weight: .bold)
        }
    }

    private static func tokenColor(for token: MarkdownInlineDisplay.LeadingToken) -> NSColor {
        switch token {
        case .uncheckedChecklist:
            return .systemRed
        case .checkedChecklist:
            return .systemGreen
        case .bullet:
            return .systemRed
        }
    }

    private static func hiddenMarkdownAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 1, weight: .regular),
            .foregroundColor: NSColor.clear,
            .kern: -0.4
        ]
    }

    private static func dividerContentAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 1, weight: .regular),
            .foregroundColor: NSColor.clear,
            .kern: -0.4
        ]
    }

    private static func codeFenceLineAttributes(isClosingFence: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 1, weight: .regular),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: codeFenceParagraphStyle(isClosingFence: isClosingFence)
        ]
    }

    private static func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.02
        style.paragraphSpacing = 6
        return style
    }

    private static func headingParagraphStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 0.96
        style.paragraphSpacing = level == 1 ? 12 : 8
        style.paragraphSpacingBefore = level == 1 ? 12 : 8
        return style
    }

    private static func codeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let font = codeBlockFont()
        let lineHeight = ceil(font.ascender - font.descender + font.leading + 3)
        style.lineHeightMultiple = 1.02
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.firstLineHeadIndent = 10
        style.headIndent = 10
        style.paragraphSpacing = 1
        return style
    }

    private static func dividerParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 16
        style.maximumLineHeight = 16
        style.paragraphSpacing = 6
        style.paragraphSpacingBefore = 1
        return style
    }

    private static func codeFenceParagraphStyle(isClosingFence: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 1
        style.maximumLineHeight = 1
        style.paragraphSpacing = isClosingFence ? 12 : 0
        style.paragraphSpacingBefore = 0
        return style
    }

    private static func addSpacingBeforeParagraph(
        in lineRange: NSRange,
        amount: CGFloat,
        to attributed: NSMutableAttributedString
    ) {
        guard lineRange.length > 0 else { return }

        let existingStyle = (attributed.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)
            ?? baseParagraphStyle()
        let style = existingStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, amount)
        attributed.addAttribute(.paragraphStyle, value: style, range: lineRange)
    }
}

private func visibleLineContentRange(for lineRange: NSRange, in text: NSString) -> NSRange {
    var contentRange = lineRange

    while contentRange.length > 0 {
        let lastCharacter = text.character(at: NSMaxRange(contentRange) - 1)
        if lastCharacter == 10 || lastCharacter == 13 {
            contentRange.length -= 1
        } else {
            break
        }
    }

    return contentRange
}

private func lineContentRange(for lineRange: NSRange, in text: NSString) -> NSRange {
    var contentRange = lineRange

    while contentRange.length > 0 {
        let lastCharacter = text.character(at: NSMaxRange(contentRange) - 1)
        if lastCharacter == 10 || lastCharacter == 13 {
            contentRange.length -= 1
        } else {
            break
        }
    }

    return contentRange
}

private func isCodeFenceLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
}
