# Auto Playlist Feature

## Overview
This feature automatically creates playlists based on folder structure in the VLC iOS app. When users create folders in the Documents directory (via Files app, iTunes, or other file management tools), the app will automatically scan these folders and create playlists with matching names containing all playable media files.

## How It Works

### Automatic Scanning
- The feature triggers when the media library completes discovery
- It also scans when the app enters foreground (to catch files added via Files app)
- New media additions also trigger scanning

### Folder Processing
1. Scans the Documents directory for folders
2. Skips system folders (`.Trash`, `Logs`, hidden folders starting with `.`)
3. For each valid folder, checks if it contains media files
4. Creates a playlist with the folder name if media files are found
5. Recursively includes media files from subfolders

### Supported Media Types
- **Video**: mp4, m4v, mov, avi, mkv, wmv, flv, webm, 3gp, mpg, mpeg, m2v, vob
- **Audio**: mp3, m4a, aac, flac, wav, ogg, wma, aiff, opus

### Playlist Management
- Prevents duplicate playlist creation (checks if playlist with folder name already exists)
- Only creates playlists for folders that actually contain media files
- Maintains a list of processed folders to avoid redundant scanning

## Implementation Details

### Key Files
- `Sources/Media Library/AutoPlaylistService.swift` - Main service implementation
- `Sources/Media Library/MediaLibraryService.swift` - Integration points
- `Sources/Media Library/AutoPlaylistServiceTests.swift` - Test utilities (DEBUG only)

### Integration Points
1. **MediaLibraryService initialization** - Creates AutoPlaylistService instance
2. **Discovery completion** - Triggers automatic scanning
3. **Foreground notification** - Rescans for new folders
4. **Media addition** - Triggers scanning when new media is detected

### API Methods
- `scanForFolderPlaylists()` - Manually trigger scanning
- `resetAutoPlaylistProcessedFolders()` - Reset processed folder cache for complete rescan

## User Experience

### Scenario 1: Desktop File Management
1. User connects iPhone to computer
2. User creates folder "Great Songs" in VLC Documents
3. User copies MP3 files into the folder
4. User opens VLC iOS app
5. App automatically creates "Great Songs" playlist with all MP3 files

### Scenario 2: Files App Usage
1. User opens Files app on iOS
2. User creates folder "Movie Collection" in VLC directory
3. User copies video files into the folder
4. User switches to VLC app
5. App detects new folder and creates "Movie Collection" playlist

## Benefits
- **Zero user configuration** - Works automatically without setup
- **Maintains organization** - Preserves user's folder-based organization in playlists
- **Cross-platform workflow** - Supports desktop file management workflows
- **Non-intrusive** - Only creates playlists for folders with media, skips system folders

## Technical Considerations
- Runs scanning on background queue to avoid blocking UI
- Uses existing MediaLibraryService infrastructure
- Follows VLC iOS coding conventions and patterns
- Minimal impact on existing codebase
- Respects existing playlist functionality