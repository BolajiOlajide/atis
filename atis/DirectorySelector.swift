//
//  DirectorySelector.swift
//  atis
//
//  Created by Bolaji Olajide on 27/07/2024.
//

import Foundation
import SwiftUI
import ID3TagEditor

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let name: String
    let size: Int64
    var key: String?
    var bpm: String?
    var children: [FileItem]?
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
    
    mutating func readID3Tags() {
        self.key = "5A"
        self.bpm = "120"
//        guard !isDirectory && url.pathExtension.lowercased() == "mp3" else { return }
//        
//        do {
//            let id3TagEditor = try ID3TagEditor(path: url.path)
//            let id3Tag = try id3TagEditor.read(version: .v2)
//            
//            // Try to read BPM
//            if let bpmFrame = id3Tag?.frames[.BPM] as? ID3FrameWithStringContent {
//                self.bpm = bpmFrame.content
//            }
//            
//            // Try to read Key
//            // Serato might store the key in a custom TXXX frame
//            if let txxxFrames = id3Tag?.frames[.TXXX] as? [ID3FrameWithStringContent] {
//                for frame in txxxFrames {
//                    if frame.description == "KEY" {
//                        self.key = frame.content
//                        break
//                    }
//                }
//            }
//        } catch {
//            print("Error reading ID3 tags for \(name): \(error)")
//        }
    }
}

struct DirectorySelector: View {
    @State private var isPresented = false
    @State private var selectedURL: URL?
    @State private var bookmarkData: Data?
    @State private var showHiddenFiles = false
    @State private var directoryContents: [FileItem] = []
    @State private var selectedSubdirectory: FileItem?
    @State private var subdirectoryContents: [FileItem] = []
    @State private var rootDirectory: FileItem?
        @State private var expandedItems = Set<UUID>()

    var body: some View {
            VStack {
                Button("Select Directory") {
                    isPresented = true
                }
                
                if let root = rootDirectory {
                    List {
                        fileItemRow(item: root)
                    }
                }
                
                if let url = selectedURL {
                    Text("Selected directory: \(url.path)")
                        .padding(.bottom)
                    
                        Table(directoryContents) {
                            TableColumn("Name") { item in
                                HStack {
                                    Image(systemName: item.isDirectory ? "folder" : "doc")
                                    Text(item.name)
                                }
                            }
                            TableColumn("Size") { item in
                                Text(item.isDirectory ? "--" : formatFileSize(item.size))
                            }
                            TableColumn("Key") { item in
                                Text(item.key ?? "--")
                            }
                            TableColumn("BPM") { item in
                                Text(item.bpm ?? "--")
                            }
                        }
                        .onChange(of: selectedSubdirectory) { _, newValue in
                            if let newDir = newValue, newDir.isDirectory {
                                loadSubdirectoryContents(url: newDir.url)
                            } else {
                                subdirectoryContents = []
                            }
                        }
                    }
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                rootDirectory = loadDirectory(url: url)
//                selectedURL = url
//                createBookmark(for: url)
//                loadDirectoryContents(url: url)
            case .failure(let error):
                print("Error selecting directory: \(error.localizedDescription)")
            }
        }
        .onAppear {
            if let bookmarkData = UserDefaults.standard.data(forKey: "selectedDirectoryBookmark") {
                self.bookmarkData = bookmarkData
                resolveBookmark()
            }
        }
    }
    
    @ViewBuilder
    private func fileItemRow(item: FileItem) -> some View {
        if item.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedItems.contains(item.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedItems.insert(item.id)
                            if item.children == nil {
                                loadChildren(for: item)
                            }
                        } else {
                            expandedItems.remove(item.id)
                        }
                    }
                )
            ) {
                ForEach(item.children ?? []) { child in
                    fileItemRow(item: child)
                }
            } label: {
                Label(item.name, systemImage: "folder")
            }
        } else {
            HStack {
                Image(systemName: "doc")
                Text(item.name)
                Spacer()
                Text(item.key ?? "--")
                Text(item.bpm ?? "--")
            }
        }
    }
    
    private func loadChildren(for item: FileItem) {
        guard item.isDirectory else { return }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: item.url, includingPropertiesForKeys: nil) else { return }
        
        var children = [FileItem]()
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent.hasPrefix(".") { continue }  // Skip hidden files
            children.append(loadDirectory(url: url))
            if children.count >= 100 { break }  // Limit to first 100 items for performance
        }
        
        DispatchQueue.main.async {
            if let index = rootDirectory?.children?.firstIndex(where: { $0.id == item.id }) {
                rootDirectory?.children?[index].children = children
            } else if rootDirectory?.id == item.id {
                rootDirectory?.children = children
            }
        }
    }
    
    private func loadDirectory(url: URL) -> FileItem {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int64 ?? 0
        let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
        
        var item = FileItem(
            url: url,
            isDirectory: isDirectory.boolValue,
            name: url.lastPathComponent,
            size: size
        )
        
        if !item.isDirectory {
            item.readID3Tags()
        }
        
        return item
    }
    
    private func isValidFileType(url: URL) -> Bool {
        if isDirectory(url: url) {
            return true
        }
        switch url.pathExtension.lowercased() {
        case "mp3", "wav", "aiff", "flac", "aac", "m4a", "ogg":
            return true
        default:
            return false
        }
    }
    
    func isDirectory(url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            return resourceValues.isDirectory ?? false
        } catch {
            print("Error determining if directory: \(error)")
            return false
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
   
    private func formatDate(_ date: Date) -> String {
       let formatter = DateFormatter()
       formatter.dateStyle = .short
       formatter.timeStyle = .short
       return formatter.string(from: date)
    }
    
    private func createBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "selectedDirectoryBookmark")
            self.bookmarkData = bookmarkData
        } catch {
            print("Failed to create bookmark: \(error.localizedDescription)")
        }
    }
    
    private func resolveBookmark() {
        guard let bookmarkData = self.bookmarkData else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // Bookmark needs to be recreated
                createBookmark(for: url)
            }
            selectedURL = url
            loadDirectoryContents(url: url)
        } catch {
            print("Failed to resolve bookmark: \(error.localizedDescription)")
        }
    }
    
    private func loadDirectoryContents(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access the directory.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            
            directoryContents = try contents
                .filter { url in
                    let isHidden = (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
                    return !isHidden && isValidFileType(url: url)
                }
                .map { url -> FileItem in
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    return FileItem(
                        url: url,
                        isDirectory: resourceValues.isDirectory ?? false,
                        name: url.lastPathComponent,
                        size: Int64(resourceValues.fileSize ?? 0)
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.isDirectory && !rhs.isDirectory {
                        return true
                    } else if !lhs.isDirectory && rhs.isDirectory {
                        return false
                    } else {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                }
        } catch {
            print("Error loading directory contents: \(error.localizedDescription)")
        }
    }
    
    private func loadSubdirectoryContents(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access the subdirectory.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            
            subdirectoryContents = try contents
                .filter { url in
                    let isHidden = (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
                    return !isHidden
                }
                .map { url -> FileItem in
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    return FileItem(
                        url: url,
                        isDirectory: resourceValues.isDirectory ?? false,
                        name: url.lastPathComponent,
                        size: Int64(resourceValues.fileSize ?? 0)
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("Error loading subdirectory contents: \(error.localizedDescription)")
        }
    }
}
