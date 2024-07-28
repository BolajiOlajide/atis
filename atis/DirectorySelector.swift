//
//  DirectorySelector.swift
//  atis
//
//  Created by Bolaji Olajide on 27/07/2024.
//

import Foundation
import SwiftUI

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let name: String
    let size: Int64
    let modificationDate: Date
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
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

    var body: some View {
        NavigationView {
            VStack {
                Button("Select Directory") {
                    isPresented = true
                }
                
                if let url = selectedURL {
                    Text("Selected directory: \(url.path)")
                        .padding(.bottom)
                    
                    Toggle("Show Hidden Files", isOn: $showHiddenFiles)
                        #if compiler(>=5.9) && canImport(SwiftUI)
                        .onChange(of: showHiddenFiles) { oldValue, newValue in
                            if let url = selectedURL {
                                loadDirectoryContents(url: url)
                            }
                        }
                        #else
                        .onChange(of: showHiddenFiles) { newValue in
                            if let url = selectedURL {
                                loadDirectoryContents(url: url)
                            }
                        }
                        #endif
                    
                    VStack {
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
                            TableColumn("Modified") { item in
                                Text(formatDate(item.modificationDate))
                            }
                        }
                        .onChange(of: selectedSubdirectory) { _, newValue in
                            if let newDir = newValue, newDir.isDirectory {
                                loadSubdirectoryContents(url: newDir.url)
                            } else {
                                subdirectoryContents = []
                            }
                        }
                        
                        if let _ = selectedSubdirectory {
                            List(subdirectoryContents) { item in
                                HStack {
                                    Image(systemName: item.isDirectory ? "folder" : "doc")
                                    Text(item.name)
                                }
                            }
                        } else {
                            Text("Select a directory to view its contents")
                        }
                    }
                }
            }
            .padding()
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedURL = url
                createBookmark(for: url)
                loadDirectoryContents(url: url)
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
                    return !isHidden
                }
                .map { url -> FileItem in
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    return FileItem(
                        url: url,
                        isDirectory: resourceValues.isDirectory ?? false,
                        name: url.lastPathComponent,
                        size: Int64(resourceValues.fileSize ?? 0),
                        modificationDate: resourceValues.contentModificationDate ?? Date.distantPast
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
                        size: Int64(resourceValues.fileSize ?? 0),
                        modificationDate: resourceValues.contentModificationDate ?? Date.distantPast
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("Error loading subdirectory contents: \(error.localizedDescription)")
        }
    }
}
