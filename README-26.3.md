# CarryOn — Minecraft 26.3 Fabric / NeoForge 移植

把 [Tschipp/CarryOn](https://github.com/Tschipp/CarryOn) 从 **Minecraft 26.2** 适配到 **26.3**。

- 仓库目录：`E:\Minecraft\CarryOn-Port\CarryOn`
- 上游版本：`2.11.1`（commit `e50ddbc`）
- 产物目录：`E:\Minecraft\CarryOn-Port\jars`

## 产物

| 文件 | 目标 |
|---|---|
| `carryon-fabric-26.3-2.11.1.jar` | Fabric（`minecraft >=26.3 <27`, `java >=25`, fabric-loader `>=0.19.5`） |
| `carryon-neoforge-26.3-2.11.1.jar` | NeoForge（`minecraft [26.3, 27)`, loader `[4,)`） |

`Forge` 子模块已按要求从构建中移除（`settings.gradle` 只 `include("Common","Fabric","NeoForge")`）。
`Forge/` 源码目录保留未删，方便以后与上游同步；它不参与构建。

## 一键构建

```powershell
pwsh -File .\build-26.3.ps1 -Target All
# 或 -Target Fabric / -Target NeoForge
```

脚本会先修补 NeoForge 的工具链（见下），再依次构建，并把 jar 复制到 `jars\`。

## 版本号改动（`gradle.properties`）

| 项 | 26.2 | 26.3 |
|---|---|---|
| `minecraft_version` | 26.2 | **26.3** |
| `minecraft_version_range` | `[26.2, 27)` | `[26.3, 27)` |
| `minecraft_version_range_fabric` | `>=26.2 <27` | `>=26.3 <27` |
| `neo_form_version` | 26.2-1 | **26.3-1** |
| `fabric_version` | 0.156.0+26.2 | **0.160.3+26.3** |
| `fabric_loader_version` | 0.19.3 | **0.19.5** |
| `cloth_config_version` | 26.2.155 | **26.3.159** |
| `neoforge_version` | 26.2.0.41-beta | **26.3.0.23-beta** |
| `forge_version` | 65.1.0 | **66.0.5**（不参与构建，仅保留模板变量） |

## 源码改动

### 1. `PoseStack#mulPose(Quaternionf)` 在 26.3 被移除

文件：`Common/src/main/java/tschipp/carryon/client/render/CarryRenderHelper.java`（12 处）

`PoseStack` 现在只剩 `mulPose(Matrix4fc)` 和 `mulPose(Transformation)`，四元数重载没了。替代 API：

- `matrix.mulPose(Axis.YP.rotationDegrees(90))` → `matrix.rotateDegrees(Axis.YP, 90)`
- `matrix.mulPose(rot)`（复合四元数） → `matrix.rotate(rot)`
- `copy.mulPose(p.pose())` 不变（`Matrix4fc` 重载仍在）

> `Axis#rotationDegrees(float)` 本身还在，但 `PoseStack#rotateDegrees(Axis, float)` 语义等价且省掉一次四元数构造。

### 2. `LivingEntity#swing` 签名变化

文件：`PickupHandler.java`（3 处）、`PlacementHandler.java`（4 处）

26.3 里挥动动画由 `SwingAnimation` 组件驱动：

```java
// 26.2
player.swing(InteractionHand.MAIN_HAND, true);
// 26.3
player.swing(InteractionHand.MAIN_HAND, SwingAnimation.DEFAULT, true);
```

（与 `LivingEntity#drop` 的原版写法一致；第三个参数仍是“是否广播给自己”。）
两个文件各自补了 `import net.minecraft.world.item.component.SwingAnimation;`。

### 3. `Entity#invulnerableTime` 变成 private

文件：`PickupHandler.java`（1 处）

```java
// 26.2
if (entity.invulnerableTime != 0)
// 26.3
if (entity.getInvulnerableTime() != 0)
```

### 4. `ItemInHandRenderer` 被删除（仅 Fabric 侧）

文件：`Fabric/src/main/java/tschipp/carryon/mixin/ItemInHandRendererMixin.java`

26.3 用 `net.minecraft.client.renderer.FirstPersonHandsAndItemsRenderer` 取代了
`net.minecraft.client.renderer.ItemInHandRenderer`。同时渲染改为从抽取出的渲染状态驱动：

- 注入目标 `submitArmWithItem` 变成 **private**，并在参数表最前面多了两个状态参数
- 原 `AbstractClientPlayer` 参数不再传入，玩家要从 `PlayerRenderState#avatarRenderState` 拿
- `AvatarRenderState extends HumanoidRenderState`，因此仍可 `instanceof ICarryOnRenderState`
  （由 `PlayerRenderStateMixin` 在 `HumanoidRenderState` 上实现）取回玩家

新签名（与 26.3 字节码逐一核对）：

```
submitArmWithItem(Lnet/minecraft/client/renderer/state/level/PlayerRenderState;
                  Lnet/minecraft/client/renderer/state/level/FirstPersonHandsAndItemsRenderState;
                  FFLnet/minecraft/world/InteractionHand;FLnet/minecraft/world/item/ItemStack;F
                  Lcom/mojang/blaze3d/vertex/PoseStack;
                  Lnet/minecraft/client/renderer/SubmitNodeCollector;I)V
```

### 5. `settings.gradle`

移除 `Forge` 子项目。

## NeoForge 工具链问题（重要）

**现象**

```
> Task :NeoForge:createMinecraftArtifacts FAILED
ERROR Line: 44, <..net.minecraft.core.HolderSet$1>..contents()....net.minecraft.core.HolderSet.Named..contents()
.............; ...public in /net/minecraft/core/HolderSet.java
java.io.IOException: Compilation failed
```

**根因**：NeoForge 26.3 的 AT 文件里新增了两条规则（26.2 没有）：

```
public net.minecraft.core.HolderSet$Named contents()Ljava/util/List;
public net.minecraft.core.HolderSet$1     contents()Ljava/util/List;
```

NeoForm 26.3-1 固定使用 `net.neoforged.jst:jst-cli-bundle:2.0.6`，该版本的 JST 会把
`HolderSet$1`（匿名类）也改写为 `public`，而 Java 不允许匿名类把重写方法的可见性提得比
父类更高，于是 JDT 重编译 MC 源码时报错。**与 CarryOn 代码无关**，任意 NeoForge 26.3
mod 工程都会踩到（`26.3.0.17` ~ `26.3.0.23-beta` 全部如此）。

**解决**：把 `neoform-runtime` 里固定的 JST 提升到 `2.0.11`。`build-26.3.ps1`
会自动完成：

1. 备份并改写 `~/.gradle/caches/modules-2/files-2.1/net.neoforged/neoform-runtime/<ver>/neoform-runtime-<ver>-all.jar`
   内的 `tools.properties`：`jst-cli-bundle:2.0.6` → `2.0.11`
2. 清理 `~/.gradle/caches/neoformruntime/intermediate_results/{transformSources,recompile}_*`
   （该缓存键不含工具版本，不清理会命中旧产物）

JST 2.0.6 之后官方已迭代到 2.0.11，此问题在新版 JST 下消失。

## 已知注意点

- **没有生成 refmap**：`carryon.mixins.json` 里仍写着 `"refmap": "carryon.refmap.json"`，
  但产物 jar 内没有该文件。26.x 起运行时不再混淆（Mojang 官方名），mixin 可直接解析
  注解中的名称，因此缺失 refmap 不影响功能。开发环境启动时只有一条提示：
  `Reference map 'carryon.refmap.json' for carryon.mixins.json could not be read.`
  （原话就带 “If this is a development environment you can ignore this message”）。
  工程里也确实没配 mixin 注解处理器 —— Loom 1.17 自己也提示
  `The mixin annotation is no longer enabled by default`。
- `Common/src/main/java/.../PickupHandler.java` 等文件里的 javadoc 缺注释警告是
  `-Xlint` 的，与本次适配无关。

## 校验记录

### 构建

- Fabric：`BUILD SUCCESSFUL`，产出 `carryon-fabric-26.3-2.11.1.jar`
- NeoForge：`BUILD SUCCESSFUL`，产出 `carryon-neoforge-26.3-2.11.1.jar`

### 静态校验（对 26.3 deobf jar 用 `javap` 逐一核对）

mixin 注入目标方法全部存在：

`Entity#startRiding / positionRider / getDismountLocationForPassenger / onPassengerTurned`、
`Inventory#getFreeSlot / addAndPickItem / pickSlot / setSelectedSlot`、
`Player#readAdditionalSaveData / stopRiding`、`HumanoidModel#setupAnim`、
`FirstPersonHandsAndItemsRenderer#submitArmWithItem`、`Screen#init` —— 全部 OK

### 运行时验证（Fabric dev 客户端，`.\gradlew.bat :Fabric:runClient`）

- `Loading Minecraft 26.3 with Fabric Loader 0.19.5`，51 个 mod，`carryon 2.11.1` 正常加载
- 图形栈初始化成功：`OpenGL` / `NVIDIA GeForce RTX 2060`
- 进入世界：`Player943 logged in with entity id 1`，退出时正常 shutdown
- **无任何 mixin 注入失败**（无 `InvalidInjectionException` / `MixinApplyError`），
  `Fabric/run/crash-reports` 为空
- 游戏内实际功能（拾取/搬运/放置、第一人称与第三人称手臂渲染）已由使用者实机确认可用
