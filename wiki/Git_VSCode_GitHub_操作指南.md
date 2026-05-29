# VS Code 中使用 Git 与 GitHub 远程仓库交互操作指南

> 适用对象：初学者到进阶开发者
> 
> 目标：在 VS Code 中完成日常 Git/GitHub 协作（本地开发、分支管理、推送拉取、标签发布、问题排查）

---

## 0. 准备工作

### 0.1 安装与配置

1. 安装 Git：<https://git-scm.com/>
2. 安装 VS Code：<https://code.visualstudio.com/>
3. 在终端验证：
   - `git --version`
4. 配置身份（首次必做）：
   - `git config --global user.name "YourName"`
   - `git config --global user.email "you@example.com"`
5. 建议设置默认分支名：
   - `git config --global init.defaultBranch main`

### 0.2 认证方式（GitHub）

推荐两种：

- HTTPS + Personal Access Token（PAT）
- SSH Key（更适合长期使用）

#### SSH 快速流程示例

1. 生成密钥：
   - `ssh-keygen -t ed25519 -C "you@example.com"`
2. 启动代理并添加私钥（Windows 可用 Git Bash 或 PowerShell 环境）
3. 复制公钥内容（`~/.ssh/id_ed25519.pub`）到 GitHub：
   - GitHub → Settings → SSH and GPG keys → New SSH key
4. 测试连接：
   - `ssh -T git@github.com`

---

## 1. Git 基本操作命令（含流程示例）

本节覆盖你提出的核心命令：暂存、提交、推送、拉取、克隆、取消提交、取消暂存、取消推送、关联远程仓库等。

### 1.1 克隆仓库（Clone）

**作用**：把 GitHub 远程仓库完整复制到本地。

- 命令：
  - `git clone https://github.com/<owner>/<repo>.git`
  - 或 `git clone git@github.com:<owner>/<repo>.git`

**流程示例**：

1. 在 VS Code 打开终端
2. 执行克隆命令
3. 进入目录：`cd <repo>`
4. 在 VS Code 打开该目录

---

### 1.2 查看状态（Status）

**作用**：查看哪些文件修改了、是否已暂存。

- 命令：`git status`

**说明**：

- `Changes not staged`：改了但没暂存
- `Changes to be committed`：已暂存，等待提交

---

### 1.3 暂存（Stage）

**作用**：把本次要提交的文件加入“提交清单”。

- 常用命令：
  - `git add <file>`：暂存单个文件
  - `git add .`：暂存当前目录下全部变更

**流程示例**：

1. 修改 `a.sv`、`b.sv`
2. 只想先提交 `a.sv`：`git add a.sv`
3. `git status` 确认 `a.sv` 已进入 staged

---

### 1.4 提交（Commit）

**作用**：把暂存区快照写入本地历史。

- 命令：`git commit -m "feat: add i2c smoke sequence"`

**建议**：提交信息遵循“动词 + 目的”，例如：

- `fix: correct nack handling`
- `refactor: split monitor logic`

---

### 1.5 推送（Push）

**作用**：把本地提交上传到远程仓库。

- 首次推送并建立跟踪：
  - `git push -u origin main`
- 后续推送：
  - `git push`

**流程示例**：

1. `git add .`
2. `git commit -m "fix: update reg_file test"`
3. `git push`

---

### 1.6 拉取（Pull）

**作用**：把远程最新变更同步到本地（本质是 fetch + merge/rebase）。

- 命令：
  - `git pull`
  - `git pull --rebase`（推荐保持更线性历史）

**建议流程**：

1. 开始编码前先 `git pull --rebase`
2. 开发提交后再 `git push`

---

### 1.7 关联/添加远程仓库（Remote）

**场景**：本地项目已存在，但还没有连接 GitHub。

- 新增远程：
  - `git remote add origin https://github.com/<owner>/<repo>.git`
- 查看远程：
  - `git remote -v`
- 修改远程地址：
  - `git remote set-url origin git@github.com:<owner>/<repo>.git`

**流程示例**：

1. `git init`
2. `git add .`
3. `git commit -m "init: first commit"`
4. `git remote add origin ...`
5. `git push -u origin main`

---

### 1.8 取消暂存（Unstage）

**作用**：撤回 `git add`，但保留工作区修改。

- 命令：
  - `git restore --staged <file>`
  - 老写法：`git reset HEAD <file>`

---

### 1.9 取消提交（Undo Commit）

根据是否保留改动，分三类：

1. **撤销最后一次提交，但保留已暂存**
   - `git reset --soft HEAD~1`
2. **撤销最后一次提交，改动回到未暂存**
   - `git reset --mixed HEAD~1`
3. **彻底丢弃最后一次提交及改动（危险）**
   - `git reset --hard HEAD~1`

---

### 1.10 取消推送（Undo Pushed Commit）

#### 安全方式（推荐）：`revert`

**作用**：追加一个“反向提交”，不改写公共历史。

- `git revert <commit-id>`
- 然后 `git push`

#### 强制回退远程（谨慎）：`reset + push --force`

- `git reset --hard <target-commit>`
- `git push --force-with-lease`

> 仅在你明确知道影响范围（例如个人分支）时使用。

---

## 2. 分支与标签：含义、作用、基本操作

## 2.1 分支（Branch）

### 含义

分支是“可移动的提交指针”。每个分支可以并行开发，互不干扰。

### 作用

- 主分支（`main`）：稳定可发布
- 功能分支（`feature/*`）：开发新功能
- 修复分支（`hotfix/*`）：紧急修复

### 常用操作

- 查看分支：`git branch`
- 创建分支：`git branch feature/i2c-scoreboard`
- 创建并切换：`git switch -c feature/i2c-scoreboard`
- 切换分支：`git switch main`
- 合并分支：`git merge feature/i2c-scoreboard`
- 删除本地分支：`git branch -d feature/i2c-scoreboard`
- 删除远程分支：`git push origin --delete feature/i2c-scoreboard`

### 分支协作流程示例

1. 从 `main` 拉最新：`git switch main ; git pull --rebase`
2. 新建功能分支：`git switch -c feature/add-rand-burst-seq`
3. 开发 + 提交：`git add . ; git commit -m "feat: add random burst sequence"`
4. 推送分支：`git push -u origin feature/add-rand-burst-seq`
5. 在 GitHub 发起 Pull Request
6. 合并后回本地：`git switch main ; git pull`
7. 删除已完成分支

### 分支合并决策图（项目实战）

> 目标：在你当前仓库里，遇到“我要把这个分支并到哪里、怎么并”时，按下面流程快速决策。

```text
开始
  |
  |-- 1) 这是共享分支（main/release/他人也在用）吗？
  |       |
  |       |-- 是 --> 优先用 merge，不改写公共历史
  |       |           命令：git switch main
  |       |                 git pull --rebase
  |       |                 git merge feature/xxx
  |       |                 git push
  |       |
  |       |-- 否（个人分支） --> 可用 rebase 整理历史后再合并
  |                   命令：git switch feature/xxx
  |                         git rebase main
  |                         git push --force-with-lease
  |                         （再发 PR）
  |
  |-- 2) 两边都改了同一文件同一位置吗？
  |       |
  |       |-- 否 --> Git 自动合并，做功能回归测试后提交
  |       |
  |       |-- 是 --> 处理冲突
  |                 步骤：编辑冲突块 <<<<<<< ======= >>>>>>>
  |                      git add <冲突文件>
  |                      git commit（或 git rebase --continue）
  |
  |-- 3) 只是想“挑某几个提交”而不是整分支？
  |       |
  |       |-- 是 --> git cherry-pick <commit-id>
  |       |-- 否 --> 继续常规 merge/PR
  |
  |-- 4) 发现已合并提交有问题，且已推送远程？
          |
          |-- 用 git revert <commit-id>（推荐，安全）
          |-- 非必要不要直接 reset + force push 到公共分支
```

#### 快速判断口诀

- **公共分支看稳定**：优先 `merge`，避免改写历史。
- **个人分支看整洁**：可 `rebase` 后再提 PR。
- **只拿单提交**：用 `cherry-pick`。
- **已推送要回退**：优先 `revert`。

#### 与 VS Code 操作对应

1. Source Control 里先看变更是否干净；
2. 底部分支入口切换到目标分支（通常 `main`）；
3. 先 Pull（建议 Rebase）；
4. 执行 Merge（或命令行执行）；
5. 若出现冲突，在编辑器冲突视图里选“接受当前/传入/两者”；
6. 完成后提交并 Push。

---

## 2.2 标签（Tag）

### 含义

标签用于给某个提交打“版本里程碑”（如 `v1.0.0`）。

### 作用

- 发布版本
- 回溯历史版本
- CI/CD 发布依据

### 常用操作

- 列出标签：`git tag`
- 创建轻量标签：`git tag v1.0.0`
- 创建附注标签（推荐）：`git tag -a v1.0.0 -m "release v1.0.0"`
- 推送单个标签：`git push origin v1.0.0`
- 推送全部标签：`git push origin --tags`
- 删除本地标签：`git tag -d v1.0.0`
- 删除远程标签：`git push origin :refs/tags/v1.0.0`

### 标签发布流程示例

1. 确保 `main` 已是可发布状态
2. `git tag -a v1.2.0 -m "release v1.2.0"`
3. `git push origin v1.2.0`
4. 在 GitHub Releases 基于该标签发布说明

---

## 3. Git 常见常用命令速查（附使用场景）

### 3.1 历史与差异

- `git log --oneline --graph --decorate --all`
  - 图形化看历史与分支关系
- `git show <commit-id>`
  - 看某次提交详情
- `git diff`
  - 看工作区改动
- `git diff --staged`
  - 看暂存区改动

### 3.2 远程同步

- `git fetch`
  - 仅抓取远程，不自动合并
- `git pull --rebase`
  - 先抓取再变基，减少 merge commit
- `git push --force-with-lease`
  - 比 `--force` 更安全的强推

### 3.3 现场保护

- `git stash push -m "wip: monitor debug"`
  - 临时保存当前改动
- `git stash list`
- `git stash pop`

### 3.4 文件恢复

- `git restore <file>`
  - 丢弃工作区该文件改动
- `git restore --source <commit-id> <file>`
  - 从某提交恢复指定文件

### 3.5 提交整理

- `git commit --amend`
  - 修改最近一次提交信息或补充内容
- `git rebase -i HEAD~N`
  - 交互式整理最近 N 次提交（合并、改注释、重排）

---

## 4. VS Code 中的 Git 操作映射

即使命令行最稳，VS Code 图形入口也很高效：

1. 左侧 Source Control 面板可查看变更
2. 点击 `+` 暂存（Stage）文件
3. 输入提交信息后点击 Commit
4. 底部状态栏可 Push/Pull/Sync
5. 分支名区域可切换/创建分支
6. 冲突文件可使用内置 Compare 界面解决

> 建议：关键操作（如 rebase、reset、force push）优先使用命令行，行为更可控。

---

## 5. 常见问题与解决方案（含流程）

## 5.1 `push` 被拒绝（non-fast-forward）

**现象**：远程有新提交，本地落后。

**处理流程**：

1. `git pull --rebase`
2. 解决冲突（若有）
3. `git add <resolved-files>`
4. `git rebase --continue`
5. `git push`

---

## 5.2 合并/变基冲突（Conflict）

**处理流程**：

1. `git status` 查看冲突文件
2. 打开文件处理 `<<<<<<< ======= >>>>>>>` 区块
3. `git add <file>` 标记已解决
4. merge 场景：`git commit`
5. rebase 场景：`git rebase --continue`

**放弃操作**：

- 放弃 merge：`git merge --abort`
- 放弃 rebase：`git rebase --abort`

---

## 5.3 提交到错误分支

### 情况 A：未推送

1. 记住错误提交 ID
2. 切到正确分支：`git switch correct-branch`
3. `git cherry-pick <commit-id>`
4. 回错误分支，回退：`git reset --hard HEAD~1`

### 情况 B：已推送

- 推荐 `git revert <commit-id>`，再在正确分支补提。

---

## 5.4 误执行 `reset --hard` 后找回提交

1. `git reflog` 查历史引用
2. 找到丢失提交的 SHA
3. `git reset --hard <sha>` 或 `git checkout -b rescue/<name> <sha>`

---

## 5.5 远程地址配错/仓库迁移

1. `git remote -v` 查看当前地址
2. `git remote set-url origin <new-url>`
3. `git fetch --all --prune` 验证

---

## 5.6 大文件误提交

1. 先停止继续推送
2. 从最新提交移除文件（并加入 `.gitignore`）
3. 若已进入历史，使用 `git filter-repo` 或 BFG 清理
4. 通知协作者重新同步历史

---

## 6. 推荐工作流（团队协作）

## 6.1 日常循环

1. `git switch main`
2. `git pull --rebase`
3. `git switch -c feature/<topic>`
4. 开发 + 小步提交
5. `git push -u origin feature/<topic>`
6. 发起 PR，代码评审
7. 合并后删除分支

## 6.2 提交信息建议（简版 Conventional Commits）

- `feat:` 新功能
- `fix:` 修复
- `docs:` 文档
- `refactor:` 重构
- `test:` 测试
- `chore:` 杂项维护

示例：

- `feat(i2c): add illegal address sequence`
- `fix(tb): correct sda sample timing`

---

## 7. 高风险命令清单（务必谨慎）

- `git reset --hard`
- `git push --force` / `git push --force-with-lease`
- `git clean -fd`
- 历史重写相关（`rebase -i`、`filter-repo`）

建议先执行：

1. `git status`
2. `git branch backup/<date>` 做备份分支
3. 再进行高风险操作

---

## 8. 一页式命令清单（可直接复用）

- 初始化：`git init`
- 克隆：`git clone <url>`
- 状态：`git status`
- 暂存：`git add .`
- 提交：`git commit -m "msg"`
- 推送：`git push`
- 拉取：`git pull --rebase`
- 分支：`git switch -c <branch>`
- 合并：`git merge <branch>`
- 标签：`git tag -a v1.0.0 -m "release" ; git push origin v1.0.0`
- 取消暂存：`git restore --staged <file>`
- 取消提交：`git reset --soft HEAD~1`
- 回滚已推送：`git revert <commit>`
- 临时保存：`git stash push -m "wip" ; git stash pop`
- 查找恢复点：`git reflog`

---

## 9. 结语

如果你主要在 VS Code 中操作，建议采用：

- **普通操作走图形界面**（看差异、暂存、提交、同步）
- **关键变更走命令行**（rebase/reset/revert/force push）

这样能兼顾效率与可控性，降低误操作风险。