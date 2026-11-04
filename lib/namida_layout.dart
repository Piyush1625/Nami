import 'package:flutter/material.dart';

class NamidaLayout extends StatelessWidget {
  const NamidaLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar.large(
                backgroundColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                expandedHeight: 140.0,
                pinned: true,
                flexibleSpace: const FlexibleSpaceBar(
                  titlePadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  title: Text(
                    'Good Morning',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              
              // Liquid Glass Mornye Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(13),
                      border: Border.all(color: Colors.white.withAlpha(26), width: 1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: const Text('Mornye Hub (.sflx)', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),

              // Placeholder for Track List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(12), // Rounded chunky squares
                        ),
                      ),
                      title: Text('Track \$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text('Artist', style: TextStyle(color: Colors.white.withAlpha(179))),
                    );
                  },
                  childCount: 20,
                ),
              ),
            ],
          ),

          // Floating Mini-Player (Liquid Glass)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 64,
                color: Colors.white.withAlpha(26), // Translucent
                // In a real app, wrap this Container with BackdropFilter for the blur!
                child: const Center(
                  child: Text('Floating Player', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
