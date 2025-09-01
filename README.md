# Cost Curve (cocu)

Cost Curve (cocu) is a simple mobile app built with Flutter to help you track price changes of household items you regularly purchase. Easily add items, record price history, and visualize trends over time.

## Features

- Add, view, update, and delete items
- Record and view price history for each item
- Search items
- View price history charts for items
- PIN-based authentication for privacy
- Local storage using SQLite

## Setup Instructions

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>=3.10.0)
- Android Studio or Xcode (for running on Android/iOS)

### Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/julesntare/cocu.git
   cd cocu
   ```

2. **Install dependencies:**

   ```bash
   flutter pub get
   ```

3. **Run the app:**

   - For Android:

     ```bash
     flutter run
     ```

   - For iOS:

     ```bash
     flutter run
     ```

### Project Structure

- `lib/models/` - Data models (Item, PriceHistory)
- `lib/screens/` - UI screens (Home, Add Item, Item Detail, History, Search, PIN)
- `lib/services/` - Database service (SQLite)
- `lib/utils/` - Utility functions
- `assets/icon/` - App icon

## Contributing

Feel free to open issues or submit pull requests for improvements or new features.

## License

This project is licensed under the MIT License.
