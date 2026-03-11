FROM golang:1.19-alpine

# 使用国内 Go 模块代理，避免访问 proxy.golang.org 超时
ENV GOPROXY=https://goproxy.cn,direct

# 设置工作目录
WORKDIR /app

# 仅复制 go.mod（不强制要求 go.sum 存在）
COPY go.mod ./

# 下载依赖（会自动生成 go.sum）
RUN go mod download

# 复制源代码
COPY . .

# 构建应用
RUN go build -o main .

# 暴露端口
EXPOSE 8080

# 运行应用
CMD ["./main"]