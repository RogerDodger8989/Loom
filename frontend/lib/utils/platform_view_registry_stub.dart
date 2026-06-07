class platformViewRegistry {
  static void registerViewFactory(String viewId, dynamic Function(int) cb) {
    // No-op on non-web platforms
  }
}
