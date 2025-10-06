/*****************************************************************************
 * AutoPlaylistServiceTests.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2024 VideoLAN. All rights reserved.
 *
 * Authors: Auto Playlist Feature Tests
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#if DEBUG
import Foundation

class AutoPlaylistServiceTests {
    
    /// Test method to verify the auto playlist service functionality
    /// This method should be called manually for testing purposes
    static func runTests() {
        print("AutoPlaylistServiceTests: Starting tests...")
        
        testMediaFileDetection()
        testFolderFiltering()
        
        print("AutoPlaylistServiceTests: All tests completed")
    }
    
    private static func testMediaFileDetection() {
        print("Testing media file detection...")
        
        let service = AutoPlaylistService(mediaLibraryService: MediaLibraryService())
        
        // Test supported media file extensions
        let testFiles = [
            "song.mp3",
            "movie.mp4", 
            "audio.flac",
            "video.mkv",
            "document.txt", // Should not be detected
            "image.jpg",    // Should not be detected
            "music.m4a",
            "film.avi"
        ]
        
        let expectedMediaFiles = ["song.mp3", "movie.mp4", "audio.flac", "video.mkv", "music.m4a", "film.avi"]
        
        for file in testFiles {
            let isMedia = service.isMediaFile(fileName: file)
            let shouldBeMedia = expectedMediaFiles.contains(file)
            
            if isMedia == shouldBeMedia {
                print("✅ \(file): correctly identified as \(isMedia ? "media" : "non-media")")
            } else {
                print("❌ \(file): incorrectly identified as \(isMedia ? "media" : "non-media")")
            }
        }
    }
    
    private static func testFolderFiltering() {
        print("Testing folder filtering...")
        
        let service = AutoPlaylistService(mediaLibraryService: MediaLibraryService())
        
        let testFolders = [
            "Great Songs",     // Should be processed
            "My Movies",       // Should be processed  
            ".Trash",          // Should be skipped
            "Logs",            // Should be skipped
            ".hidden",         // Should be skipped
            "Music Collection" // Should be processed
        ]
        
        let expectedProcessable = ["Great Songs", "My Movies", "Music Collection"]
        
        for folder in testFolders {
            let shouldProcess = service.shouldProcessFolder(named: folder)
            let expectedToProcess = expectedProcessable.contains(folder)
            
            if shouldProcess == expectedToProcess {
                print("✅ \(folder): correctly \(shouldProcess ? "will be" : "will not be") processed")
            } else {
                print("❌ \(folder): incorrectly \(shouldProcess ? "will be" : "will not be") processed")
            }
        }
    }
}

// Extension to expose private methods for testing
extension AutoPlaylistService {
    func isMediaFile(fileName: String) -> Bool {
        return self.isMediaFile(fileName: fileName)
    }
    
    func shouldProcessFolder(named folderName: String) -> Bool {
        return self.shouldProcessFolder(named: folderName)
    }
}

#endif