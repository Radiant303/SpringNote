// Diagnostic integration test: measures the real process memory curve while
// cycling the notes workspace modes (编辑 / 分栏 / 预览) with a springtree
// block on screen.
//
// Run with:
//   flutter test integration_test/memory_churn_test.dart -d windows
//
// It prints one line per sample: cycle, RSS, Dart heap usage and external
// (native-backed) usage. A healthy sawtooth returns to a flat trough after
// forced GCs; a trough that keeps rising means retained growth.
import 'dart:developer' as developer;
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/notes_page.dart';
import 'package:vm_service/vm_service_io.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _buildNote() {
  return r'''
# 2026-07-27 日报

```springtree
- 人工智能生态系统
  - 基础理论
    - 数学基础
      - 线性代数
        - 向量空间
          - 基向量
            - 正交基
              - Gram-Schmidt 正交化
                - 数值稳定性分析
                  - 浮点误差传播
                  - 条件数优化
            - 特征向量
              - 特征值分解
                - 对称矩阵分解
                - 奇异值分解
                  - PCA降维
                    - 主成分选择策略
                      - 方差贡献率
                      - 累计贡献率
      - 概率统计
        - 贝叶斯理论
          - 贝叶斯网络
            - 条件独立关系
              - 有向无环图
                - 概率推理算法
                  - 精确推理
                    - 变量消除
                    - 联合树算法
                  - 近似推理
                    - 蒙特卡洛采样
                      - MCMC
                        - Metropolis-Hastings
                        - Gibbs Sampling
        - 信息论
          - 信息熵
            - 交叉熵
              - KL散度
                - JS散度
                  - 模型分布对齐
                    - 生成模型优化

  - 机器学习
    - 监督学习
      - 分类算法
        - 逻辑回归
          - 二分类
          - 多分类
            - Softmax
              - 温度参数调整
                - 校准概率输出
        - 支持向量机
          - 线性核
          - 非线性核
            - RBF核
              - 高维映射空间
      - 回归算法
        - 线性回归
          - 岭回归
          - Lasso回归
        - 集成学习
          - 随机森林
            - 决策树构建
              - 特征选择
                - 信息增益
                - 基尼指数
          - Boosting
            - AdaBoost
            - Gradient Boosting
              - XGBoost
                - 分裂策略
                - 正则化机制

    - 无监督学习
      - 聚类
        - K-Means
          - 初始化策略
            - K-Means++
          - 聚类中心更新
        - DBSCAN
          - 核心点
          - 边界点
          - 噪声点
      - 降维
        - PCA
        - t-SNE
          - 高维相似度计算
            - 低维映射优化

  - 深度学习
    - 神经网络基础
      - 感知机
        - 单层网络
        - 多层网络
          - 激活函数
            - Sigmoid
            - ReLU
              - Leaky ReLU
              - GELU
          - 损失函数
            - MSE
            - Cross Entropy
    - CNN卷积神经网络
      - 卷积操作
        - 卷积核
          - 权重共享
          - 局部感受野
      - 网络结构
        - LeNet
        - AlexNet
        - VGG
        - ResNet
          - 残差连接
            - Identity Mapping
              - 深层网络训练稳定性
        - Vision Transformer
          - Patch Embedding
            - Position Encoding

    - RNN序列模型
      - 基础RNN
      - LSTM
        - 遗忘门
        - 输入门
        - 输出门
      - GRU
        - 更新门
        - 重置门

    - Transformer
      - Encoder
        - Multi Head Attention
          - Query
          - Key
          - Value
            - 注意力权重计算
              - Scaled Dot Product Attention
        - Feed Forward Network
        - Layer Normalization
      - Decoder
        - Masked Attention
        - Cross Attention
      - 大语言模型
        - GPT系列
          - GPT-2
          - GPT-3
          - GPT-4
        - Qwen系列
          - Qwen2
          - Qwen3
            - Base模型
            - Instruct模型
            - Reasoning模型
              - 思考链生成
                - 长上下文推理
        - 模型训练
          - 预训练
            - 数据清洗
              - 去重
              - 质量过滤
          - 指令微调
            - SFT
              - 数据构造
                - Prompt模板
                - Response生成
          - 对齐训练
            - RLHF
              - Reward Model
              - PPO
            - DPO
              - 偏好数据优化

  - AI Agent智能体系统
    - Agent架构
      - 感知层
        - 输入解析
          - 文本
          - 图片
          - 音频
      - 推理层
        - Planning
          - 任务拆解
            - 子任务生成
              - DAG规划
        - Memory
          - 短期记忆
            - Context Window
          - 长期记忆
            - 向量数据库
              - Embedding
                - 相似度检索
                  - RAG
      - 行动层
        - Tool Calling
          - API调用
          - MCP协议
            - Tool Registry
              - Tool Discovery
              - Tool Execution
        - Workflow
          - State Machine
          - Graph Agent
            - Node
              - Action Node
              - Decision Node
              - Interrupt Node

  - 软件工程
    - 前端
      - Flutter
        - Widget系统
          - StatelessWidget
          - StatefulWidget
        - 渲染机制
          - Element Tree
          - Render Object Tree
      - Web
        - React
          - Virtual DOM
            - Diff算法
              - Fiber架构
    - 后端
      - Java
        - JVM
          - Class Loader
          - Garbage Collector
            - G1 GC
            - ZGC
      - Spring生态
        - Spring Boot
          - Auto Configuration
        - Spring Cloud
          - Gateway
          - Nacos
          - OpenFeign
        - Spring AI
          - ChatModel
          - Agent
          - Vector Store

  - 云计算
    - 容器化
      - Docker
        - Image
        - Container
        - Layer
      - Kubernetes
        - Pod
          - Container
        - Service
        - Deployment
        - Operator
    - 云原生
      - 微服务
        - 服务发现
        - 配置中心
        - 链路追踪
      - DevOps
        - CI/CD
          - GitHub Actions
          - Jenkins
        - 自动部署
          - 蓝绿发布
          - 金丝雀发布

  - 未来方向
    - AGI
      - 通用推理
        - 世界模型
        - 自主学习
      - 多模态智能
        - 文本
        - 图像
        - 视频
        - 机器人
      - 人机协作
        - AI助手
        - AI Agent团队
        - 自动化软件开发
```
''';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notes mode switch memory curve', (tester) async {
    // Real on-disk data directory in a temp folder.
    final root = await Directory.systemTemp.createTemp('spring_note_mem');
    final daily = Directory(
      '${root.path}${Platform.pathSeparator}notes${Platform.pathSeparator}daily',
    );
    final weekly = Directory(
      '${root.path}${Platform.pathSeparator}notes${Platform.pathSeparator}weekly',
    );
    final monthly = Directory(
      '${root.path}${Platform.pathSeparator}notes${Platform.pathSeparator}monthly',
    );
    for (final dir in [daily, weekly, monthly]) {
      await dir.create(recursive: true);
    }
    final now = DateTime.now();
    final noteName =
        '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}.md';
    await File(
      '${daily.path}${Platform.pathSeparator}$noteName',
    ).writeAsString(_buildNote());

    final state = LocalDataState(
      dataDirectory: root.path,
      configPath: '${root.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: weekly.path,
      monthlyNotesDirectory: monthly.path,
      config: AppConfig.defaults(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(localDataState: state),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Connect to the VM service of this very process.
    final info = await developer.Service.getInfo();
    final serviceUri = info.serverUri;
    expect(serviceUri, isNotNull, reason: 'VM service must be enabled');
    final service = await vmServiceConnectUri(
      serviceUri.toString().replaceAll('http', 'ws'),
    );
    final vmSnapshot = await service.getVM();
    final isolateId = vmSnapshot.isolates!.first.id!;
    Future<int> rss() async =>
        (await service.getProcessMemoryUsage()).root!.size!;
    Future<int> heapUsage() async =>
        (await service.getMemoryUsage(isolateId)).heapUsage!;
    Future<int> externalUsage() async =>
        (await service.getMemoryUsage(isolateId)).externalUsage!;
    Future<void> forceGC() async {
      for (var round = 0; round < 3; round++) {
        await service.callMethod('_collectAllGarbage', isolateId: isolateId);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    String mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

    Future<void> sample(String label) async {
      await forceGC();
      // ignore: avoid_print
      print(
        'MEMCURVE $label rss=${mb(await rss())}MB '
        'heap=${mb(await heapUsage())}MB external=${mb(await externalUsage())}MB',
      );
    }

    // Warm up in preview mode, then take the baseline trough.
    await tester.tap(
      find.byKey(const ValueKey('notes-workspace-mode-preview')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await sample('baseline');

    final switchWatch = Stopwatch();
    Future<void> switchTo(String mode) async {
      switchWatch
        ..reset()
        ..start();
      await tester.tap(find.byKey(ValueKey('notes-workspace-mode-$mode')));
      // 100ms fake-time steps: animations play out over real frames, so the
      // wall-clock time approximates the real per-frame cost of a switch.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      switchWatch.stop();
      // ignore: avoid_print
      print('SWITCHTIME $mode ${switchWatch.elapsedMilliseconds}ms');
    }

    for (var cycle = 1; cycle <= 30; cycle++) {
      await switchTo('edit');
      await switchTo('split');
      await switchTo('preview');
      if (cycle % 3 == 0) {
        await sample('cycle-$cycle');
      }
    }

    await service.dispose();
  });
}
