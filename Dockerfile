# 构建阶段（支持多架构）
# OpenClaw 要求 Node>=22.12，使用 DOCKER_BUILDKIT=0 可规避代理下 "content size of zero"
ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE} AS builder

# 设置构建参数
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG OPENCLAW_DOCKER_APT_PACKAGES=""

# 打印构建信息用于调试
RUN echo "Building for: $TARGETPLATFORM on $BUILDPLATFORM"

# 仅在非 ARM 架构上安装 Bun（ARM 上强制使用 pnpm）
RUN if [ "$TARGETPLATFORM" != "linux/arm64" ]; then \
      curl -fsSL https://bun.sh/install | bash && \
      echo "/root/.bun/bin:$PATH" >> /etc/profile.d/bun.sh; \
    fi

RUN corepack enable

WORKDIR /app

# slim 镜像缺少 git/curl，需先安装（pnpm 安装 git 依赖、bun 安装脚本需要）
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git curl ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# 可选：安装额外的 apt 包
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Configure git to use HTTPS for GitHub (fixes libsignal-node SSH errors)
RUN git config --global url."https://github.com/".insteadOf ssh://git@github.com/
RUN git config --global url."https://".insteadOf git://

# 复制依赖文件并安装（利用 Docker 缓存层）
# 构建时可通过 --build-arg USE_OFFICIAL_REGISTRY=1 使用官方 npm 源（npmmirror 不稳定时）
ARG USE_OFFICIAL_REGISTRY=0
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN if [ "$USE_OFFICIAL_REGISTRY" = "1" ]; then echo "registry=https://registry.npmjs.org/" > .npmrc; fi
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# 使用 --no-frozen-lockfile 避免 patchedDependencies/settings 与 lockfile 格式不匹配（pnpm 版本差异）
# npmmirror 不稳定时可加 --build-arg USE_OFFICIAL_REGISTRY=1
RUN if [ "$USE_OFFICIAL_REGISTRY" = "1" ]; then pnpm config set registry https://registry.npmjs.org/; fi && \
    pnpm install --no-frozen-lockfile --ignore-scripts

# 显式安装 wecom 插件的依赖，确保 pnpm 正确解析到根 node_modules（避免插件加载时找不到）
RUN pnpm add -w @wecom/aibot-node-sdk@^1.0.1 --ignore-scripts

# 复制源码并构建
COPY . .

# 再次 install 以安装 extensions 的依赖（首次 install 时 extensions 尚未复制）
RUN pnpm install --no-frozen-lockfile --ignore-scripts

RUN pnpm build
# 构建飞书 extension（从根目录用 pnpm exec tsc，避免 extensions 内 tsc 找不到）
RUN [ -f extensions/feishu/tsconfig.json ] && pnpm exec tsc -p extensions/feishu/tsconfig.json || true

# 强制在所有架构上使用 pnpm 构建 UI（ARM/Synology 架构上 Bun 可能失败）
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

# 运行时阶段（最小化最终镜像大小）
ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

ARG TARGETPLATFORM

# 安装 git：Gateway 更新检查、agent workspace、skills 等依赖 git，否则报 spawn git ENOENT
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN corepack enable && \
    echo "Runtime image for: $TARGETPLATFORM"

WORKDIR /app

# 复制构建产物和扩展
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
# 复制 npm 配置（allow-build-scripts、git-protocol 等）
COPY --from=builder /app/.npmrc ./
# 复制补丁文件（pnpm patchedDependencies 需要）
COPY --from=builder /app/patches ./patches
# 复制扩展（插件）目录，包括所有已编译的依赖
COPY --from=builder /app/extensions ./extensions
# 复制运行时所需的文档（templates 用于 agent 任务）
COPY --from=builder /app/docs ./docs
# 在 runtime 阶段安装依赖，避免 COPY node_modules 在 macOS overlay2 上触发 I/O 错误
# 使用 --no-frozen-lockfile 兼容 extensions 与 lockfile 版本不一致（如 dingtalk-connector）
RUN pnpm install --no-frozen-lockfile --ignore-scripts

# 清理 pnpm 缓存以减小镜像
RUN pnpm store prune

ENV NODE_ENV=production

# 安全加固：以非 root 用户运行
# node:22-bookworm 镜像包含 'node' 用户（uid 1000）
# 这通过防止容器逃逸来减少攻击面
USER node

CMD ["node", "dist/index.js"]
