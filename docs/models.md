# 模型配置

SpringNote 支持多供应商、多模型类型和默认模型分配。你可以把智能生成、编辑补全和回忆书绑定到不同模型。

## 配置流程

<div class="flow-panel">
  <section>
    <div>
      <span>01</span>
      <h3>添加供应商</h3>
      <p>先设置供应商名称和 Base URL。SpringNote 会以供应商作为模型分组，方便同时管理多个兼容 OpenAI 协议的服务。</p>
    </div>
    <figure>
      <img src="/images/configone.png" alt="添加供应商">
    </figure>
  </section>

  <section>
    <div>
      <span>02</span>
      <h3>添加模型</h3>
      <p>填写模型 ID，并标记该模型可以承担的任务类型。不同模型可以分别用于生成、补全或回忆书问答。</p>
    </div>
    <figure>
      <img src="/images/configtwo.png" alt="添加模型">
    </figure>
  </section>

  <section>
    <div>
      <span>03</span>
      <h3>编辑能力</h3>
      <p>检查协议、模型类型和补全模式。这里决定模型在编辑器、总结和检索场景中的可用范围。</p>
    </div>
    <figure>
      <img src="/images/configthree.png" alt="编辑模型">
    </figure>
  </section>

  <section>
    <div>
      <span>04</span>
      <h3>选择默认模型</h3>
      <p>为不同 AI 场景指定默认模型。完成后，日常记录、AI 整理和回忆书会自动使用对应配置。</p>
    </div>
    <figure>
      <img src="/images/configfour.png" alt="选择默认模型">
    </figure>
  </section>
</div>
