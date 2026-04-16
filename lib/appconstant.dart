import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // Read Google API key from .env file
  static String get googleApiKey => dotenv.get('GOOGLE_API_KEY', fallback: '');
}
