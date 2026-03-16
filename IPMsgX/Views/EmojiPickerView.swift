// IPMsgX/Views/EmojiPickerView.swift
// Built-in emoji picker popover

import SwiftUI

struct EmojiPickerView: View {
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: EmojiCategory.ID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search emoji", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            .padding(8)

            if searchText.isEmpty {
                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(EmojiData.categories) { category in
                            Button {
                                selectedCategory = category.id
                            } label: {
                                Text(category.icon)
                                    .font(.system(size: 16))
                                    .frame(width: 30, height: 28)
                                    .background(
                                        selectedCategory == category.id
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(category.name)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 36)

                Divider()

                // Emoji grid for selected category
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(currentItems) { item in
                            Button {
                                onSelect(item.emoji)
                            } label: {
                                Text(item.emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .help(item.name)
                        }
                    }
                    .padding(6)
                }
            } else {
                // Search results
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(searchResults) { item in
                            Button {
                                onSelect(item.emoji)
                            } label: {
                                Text(item.emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .help(item.name)
                        }
                    }
                    .padding(6)

                    if searchResults.isEmpty {
                        Text("No emoji found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
        }
        .frame(width: 320, height: 280)
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = EmojiData.categories.first?.id
            }
        }
    }

    private var currentItems: [EmojiItem] {
        guard let id = selectedCategory,
              let category = EmojiData.categories.first(where: { $0.id == id })
        else { return EmojiData.categories.first?.items ?? [] }
        return category.items
    }

    private var searchResults: [EmojiItem] {
        let q = searchText.lowercased()
        return EmojiData.allItems.filter {
            $0.name.contains(q) || $0.emoji.contains(q)
        }
    }
}
