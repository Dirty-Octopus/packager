import SwiftUI

struct StructurePanel: View {
    @ObservedObject var project: PackageProject

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Hairline()
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.node.id) { item in
                            TreeRow(
                                node: item.node,
                                depth: item.depth,
                                isExpanded: expandedIDs.contains(item.node.id),
                                isSelected: project.selectedNodeID == item.node.id,
                                onToggle: { withAnimation(.snappy(duration: 0.16)) { project.toggleExpansion(item.node.id) } },
                                onSelect: { project.selectedNodeID = item.node.id },
                                onReveal: { project.reveal(path: item.node.path) }
                            )
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            if let node = selectedNode {
                Hairline()
                NodeDetailBar(node: node) {
                    project.reveal(path: node.path)
                }
            }
        }
        .panel()
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            SearchField(text: $project.searchText, placeholder: T("Filter structure"))
                .frame(width: 140)

            ForEach(TreeFilter.allCases, id: \.self) { filter in
                FilterChip(
                    title: filter.title,
                    symbol: filter.symbol,
                    isActive: project.treeFilter == filter
                ) {
                    withAnimation(.snappy(duration: 0.16)) {
                        project.treeFilter = filter
                    }
                }
            }

            Spacer(minLength: 2)

            Menu {
                Button(T("Expand All")) { project.expandAll() }
                Button(T("Collapse All")) { project.collapseAll() }
                Divider()
                Button(T("Reveal Original")) { project.revealSource() }
                Button(T("Reveal Workspace")) { project.revealWorkspace() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.strokeSoft, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 11)
        .frame(height: 45)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(T("No items match this filter"))
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Button(T("Clear Filter")) {
                withAnimation(.snappy(duration: 0.16)) {
                    project.searchText = ""
                    project.treeFilter = .all
                }
            }
            .buttonStyle(SoftButtonStyle(height: 26, horizontalPadding: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Derived data

    private var isFiltering: Bool {
        project.treeFilter != .all || !project.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredRoot: PackageNode? {
        guard let root = project.inspection?.root else { return nil }
        let query = project.searchText.trimmingCharacters(in: .whitespaces)
        guard isFiltering else { return root }
        return root.filtered { node in
            let matchesFilter: Bool
            switch project.treeFilter {
            case .all: matchesFilter = true
            case .binaries: matchesFilter = node.kind == .binary
            case .scripts: matchesFilter = node.kind == .script
            case .warnings: matchesFilter = node.is32Bit || node.risk != .none
            }
            let matchesQuery = query.isEmpty
                || node.name.localizedCaseInsensitiveContains(query)
                || (node.note?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesFilter && matchesQuery
        }
    }

    private var expandedIDs: Set<String> {
        guard let filteredRoot else { return [] }
        return isFiltering ? filteredRoot.allExpandableIDs : project.expanded
    }

    private var rows: [(node: PackageNode, depth: Int)] {
        guard let filteredRoot else { return [] }
        return filteredRoot.flattened(expanded: expandedIDs)
    }

    private var selectedNode: PackageNode? {
        guard let root = project.inspection?.root, let id = project.selectedNodeID else { return nil }
        return root.allNodes().first { $0.id == id }
    }
}

// MARK: - Row

struct TreeRow: View {
    let node: PackageNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    var onToggle: () -> Void
    var onSelect: () -> Void
    var onReveal: () -> Void

    @State private var hovering = false

    private var labelFont: Font {
        if node.isFileNode { return Theme.mono(10.8) }
        if node.kind == .product { return .system(size: 12.5, weight: .semibold) }
        if node.kind == .component { return .system(size: 11.8, weight: .medium) }
        return Theme.body(11.8)
    }

    var body: some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: CGFloat(depth) * 14)

            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.snappy(duration: 0.16), value: isExpanded)
                    .frame(width: 13, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(node.hasChildren ? 1 : 0)
            .disabled(!node.hasChildren)

            Image(systemName: node.kind.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(nodeTint(node))
                .frame(width: 15)

            Text(node.name)
                .font(labelFont)
                .foregroundStyle(node.kind == .truncated ? Theme.tertiaryText : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if node.kind == .binary, node.is32Bit {
                Badge(text: T("32-bit"), tint: Theme.critical)
            }
            if node.kind == .component, node.is32Bit {
                Badge(text: T("32-bit"), tint: Theme.critical)
            }
            if node.kind == .script, node.risk == .high {
                Badge(text: T("high risk"), tint: Theme.critical)
            } else if node.kind == .script, node.risk == .caution {
                Badge(text: T("review"), tint: Theme.warning)
            }
            if node.hiddenCount > 0 {
                Badge(text: "+\(node.hiddenCount)", tint: Theme.tertiaryText)
            }

            Spacer(minLength: 6)

            if hovering, node.isFileNode {
                Button(action: onReveal) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.surface)
                        )
                }
                .buttonStyle(.plain)
                .help(T("Reveal in Finder"))
            }

            if node.kind == .binary, !node.architectures.isEmpty {
                Text(node.architectures.joined(separator: "/"))
                    .font(Theme.mono(8.8))
                    .foregroundStyle(node.is32Bit ? Theme.critical.opacity(0.9) : Theme.tertiaryText)
                    .lineLimit(1)
            }

            if let size = node.size, node.kind != .product, node.kind != .folder {
                Text(Fmt.size(size))
                    .font(Theme.mono(8.8))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 29)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Theme.accentSoft : (hovering ? Theme.surfaceMuted : Color.clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail bar

struct NodeDetailBar: View {
    let node: PackageNode
    var onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: node.kind.symbol, tint: nodeTint(node), size: 29)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(node.name)
                        .font(Theme.body(11.5, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if node.is32Bit {
                        Badge(text: T("legacy arch"), tint: Theme.critical)
                    }
                }
                Text(prettyPath(node.path))
                    .font(Theme.mono(8.8))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 6)

            if !node.architectures.isEmpty {
                MetaChip(
                    text: node.architectures.joined(separator: " · "),
                    tint: node.is32Bit ? Theme.critical : Theme.secondaryText
                )
            }
            if let size = node.size {
                MetaChip(text: Fmt.size(size), tint: Theme.secondaryText)
            }
            if let note = node.note, !note.isEmpty {
                Text(P(localizedNodeNote(note)))
                    .font(Theme.body(9.3))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
            if node.isFileNode {
                Button(T("Reveal"), action: onReveal)
                    .buttonStyle(SoftButtonStyle(height: 25, horizontalPadding: 9))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(Theme.surfaceMuted)
    }
}

struct MetaChip: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(Theme.mono(8.8))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.strokeSoft, lineWidth: 1)
            )
            .lineLimit(1)
    }
}


func localizedNodeNote(_ note: String) -> String {
    if note == "Bill of materials" { return T("Bill of materials") }
    if note == "Symbolic link" { return T("Symbolic link") }
    if note == "gzip archive" { return T("gzip archive") }
    if note == "bzip2 archive" { return T("bzip2 archive") }
    if note == "xz archive" { return T("xz archive") }
    if note == "zstd archive" { return T("zstd archive") }
    if note == "raw archive" { return T("raw archive") }
    if let count = note.intValue(between: "install script") {
        return T("%d install script(s)", count)
    }
    if let count = note.intValue(between: "OS constraint") {
        return T("%d OS constraint(s)", count)
    }
    if let count = note.intValue(between: "component") {
        return T("%d component(s)", count)
    }
    if let count = note.intValue(between: "more item") {
        return T("%d more items", count)
    }
    return T(note)
}

extension String {
    func intValue(between fragment: String) -> Int? {
        guard contains(fragment) else { return nil }
        let digits = filter(\.isNumber)
        return Int(digits)
    }
}
