// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

// Manages user authentication state across the session.
class _AuthManager {
  // Returns the current user's display name, or null when no user is signed in.
  String? _getDisplayName() => null;

  // Initiates sign-out and clears the local session token.
  Future<void> _signOut() async {}

  // Reloads user credentials from the remote server.
  Future<void> _reload() async {}
}
