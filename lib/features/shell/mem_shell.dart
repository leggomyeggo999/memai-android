import 'package:flutter/material.dart';

import '../capture/capture_page.dart';
import '../chat/mem_chat_page.dart';
import '../home/pulse_page.dart';
import '../library/library_page.dart';

/// Bottom navigation: **Pulse · Capture · Chat · Library**.
///
/// Each tab owns its own [Scaffold] so app bars stay contextual; settings opens
/// from the gear on every primary screen.
class MemShell extends StatefulWidget {
  const MemShell({super.key});

  @override
  State<MemShell> createState() => _MemShellState();
}

class _MemShellState extends State<MemShell> {
  int _index = 0;

  static const _tabs = [
    PulsePage(),
    CapturePage(),
    MemChatPage(),
    LibraryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.blur_circular_outlined),
            selectedIcon: Icon(Icons.blur_circular),
            label: 'Pulse',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
