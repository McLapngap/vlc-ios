# Testing Folder-Based Playlist Feature

## Test Scenarios

### 1. Basic Folder Playlist Creation
- Create a folder named "Great Songs" in the app's documents directory
- Add several media files (mp3, mp4, etc.) to this folder
- Expected: A playlist named "Great Songs" should be automatically created with all the media files

### 2. Nested Folders
- Create a main folder with subfolders inside
- Expected: Only the main folder should get a playlist (subfolders are not scanned recursively)

### 3. Adding Files to Existing Folder
- Add new media files to a folder that already has a playlist
- Expected: The playlist should be updated to include the new files

### 4. Empty Folders
- Create an empty folder or a folder with only non-media files
- Expected: No playlist should be created

### 5. System Folders
- Verify that system folders (like .Trash, Documents) don't get playlists
- Expected: These folders should be ignored

### 6. Duplicate Names
- Create multiple folders with similar names
- Expected: Playlists should be created with unique names (e.g., "Music", "Music (1)")

## Implementation Summary

The feature includes:

1. **FolderPlaylistManager.swift**: Core logic for folder scanning and playlist creation
   - Scans folders for media files
   - Creates playlists named after folders
   - Updates playlists when new files are added
   - Maintains a list of processed folders to avoid duplicates

2. **MediaLibraryService Integration**:
   - Added `folderPlaylistManager` property
   - Integrated with file discovery mechanism
   - Scans existing folders on startup
   - Handles new folder/file additions

3. **Key Features**:
   - Automatic playlist creation from folders
   - Support for both video and audio files
   - Updates playlists when new files are added
   - Skips empty folders and system folders
   - Handles duplicate playlist names gracefully

## Usage

1. Copy a folder containing media files to the app via USB/file browser
2. The app will automatically detect the folder and create a playlist
3. The playlist will appear in the playlists section with the folder name
4. Adding more files to the folder will update the playlist automatically