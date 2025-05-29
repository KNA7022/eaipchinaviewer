# EAIP China Viewer

*[English](README.md) | [中文](README.zh-CN.md)*

![App Logo](assets/icons/icon.png)

## Overview

EAIP China Viewer is a comprehensive mobile application designed for aviation professionals and pilots to easily access, view, and manage Electronic Aeronautical Information Publication (EAIP) data for Chinese airspace. This Flutter-based application provides a seamless experience for browsing airport charts, procedures, and aviation related information, along with real-time airport weather data.

## Features

### Core Functionality
- **EAIP Document Viewing**: Browse and view official aeronautical charts and procedures
- **Version Control**: Access current and historical EAIP publications
- **Search Capability**: Quickly find specific charts or information
- **PDF Viewing**: High-quality integrated PDF viewer with zoom and navigation controls

### Weather Information
- **METAR/TAF Data**: Real-time weather reports and forecasts for airports
- **Weather Report Translation**: Automatic translation of weather reports
- **Data Caching**: Intelligent caching system for offline access and reduced data usage
- **Recent Searches**: Quick access to previously searched airports

### User Experience
- **Responsive UI**: Intuitive interface that adapts to different screen sizes
- **Dark Mode Support**: Comfortable viewing in all lighting conditions
- **Collapsible Sidebar**: Efficient navigation with adjustable sidebar
- **PDF Management**: Save, share, and organize PDF documents

### Technical Features
- **Automatic Updates**: Built-in update mechanism for app version management
- **Offline Support**: Access previously loaded content without an internet connection
- **File Management**: Efficient caching and storage of EAIP documents
- **Cross-platform**: Available for iOS, Android, macOS, and Windows

## Screenshots

*(Screenshots will be added here)*

## Installation

### Mobile (iOS & Android)
1. Download the app from the App Store (iOS) or Google Play Store (Android)
2. Alternatively, download the latest APK from the releases page for Android

### Desktop (Windows & macOS)
1. Download the appropriate installer from the releases page
2. Run the installer and follow the on-screen instructions

### For Developers
```bash
# Clone the repository
git clone https://github.com/KNA7022/eaipchinaviewer.git

# Navigate to the project directory
cd eaipchinaviewer

# Install dependencies
flutter pub get

# Run the app in debug mode
flutter run
```

## Usage

### Login
The app requires valid credentials to access the EAIP database. Contact your aviation authority or organization for access.

### Browsing EAIP Documents
1. After logging in, you'll see the available EAIP versions
2. Select a version to browse its contents
3. Navigate through the hierarchical structure to find specific documents
4. Tap/click on a document to view it in the integrated PDF viewer

### Weather Information
1. Navigate to the Weather tab
2. Enter an airport's ICAO code (e.g., ZBAA for Beijing Capital)
3. View current METAR and TAF data with translations
4. Use the refresh button to update weather information

### Settings
Customize your experience with options for:
- Theme preferences (Light/Dark/System)
- PDF viewing options
- Cache management
- Login preferences

## Privacy & Security

EAIP China Viewer includes comprehensive privacy features and secure handling of user credentials. The app requires certain permissions for optimal functionality:

- **Internet access**: For downloading EAIP data and weather information
- **Storage access**: For saving and managing PDF documents
- **Network state**: To adapt functionality based on connectivity

## Contributing

We welcome contributions to improve the EAIP China Viewer. Please feel free to submit issues or pull requests.

## License

This project is licensed under [MIT] - see the LICENSE file for details.

## Acknowledgements

- Special thanks to all contributors and testers
- Flutter and Dart teams for the excellent framework
- All third-party libraries that made this project possible
