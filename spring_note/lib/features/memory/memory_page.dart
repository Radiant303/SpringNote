import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/theme/app_theme.dart';

class MemoryPage extends StatelessWidget {
  const MemoryPage({super.key, required this.localDataState});

  final LocalDataState localDataState;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  label: const Text('记忆模型'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '开启新对话',
                  onPressed: null,
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '准备好了，随时开始',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: null,
                            icon: const Icon(Icons.add_rounded),
                          ),
                          Expanded(
                            child: Text(
                              '问问你的回忆...',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: AppTheme.textSubtle),
                            ),
                          ),
                          IconButton.filled(
                            onPressed: null,
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.text,
                            ),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '回忆书问答和 remember.json 将在第八阶段接入。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localDataState.dataDirectory,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
