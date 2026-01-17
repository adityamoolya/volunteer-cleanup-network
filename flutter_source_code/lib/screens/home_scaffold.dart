// lib/screens/home_scaffold.dart
import 'package:flutter/material.dart';
import 'feed_screen.dart';
import 'mission_screen.dart';
import 'profile_screen.dart';
import 'create_post_screen.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _currentIndex = 0;

  // Keys to refresh screens when needed
  final GlobalKey<_FeedScreenWrapperState> _feedKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          FeedScreenWrapper(key: _feedKey),
          const MissionsScreen(),
          const ProfileScreen(),
        ],
      ),
      // FAB for creating new reports
      floatingActionButton: _currentIndex == 0 
        ? FloatingActionButton.extended(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const CreatePostScreen()),
              );
              // Refresh feed if a new post was created
              if (result == true) {
                _feedKey.currentState?.refreshFeed();
              }
            },
            backgroundColor: const Color(0xFF2E7D32),
            icon: const Icon(Icons.add_a_photo, color: Colors.white),
            label: const Text(
              "Report",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: const Color(0xFF2E7D32),
          unselectedItemColor: Colors.grey,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment),
              label: 'Missions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// Wrapper to allow external refresh of FeedScreen
class FeedScreenWrapper extends StatefulWidget {
  const FeedScreenWrapper({super.key});

  @override
  State<FeedScreenWrapper> createState() => _FeedScreenWrapperState();
}

class _FeedScreenWrapperState extends State<FeedScreenWrapper> {
  Key _feedKey = UniqueKey();

  void refreshFeed() {
    setState(() {
      _feedKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FeedScreen(key: _feedKey);
  }
}