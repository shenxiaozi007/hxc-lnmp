FROM golang:1.19-alpine

# 使用国内 Go 模块代理，避免访问 proxy.golang.org 超时
ENV GOPROXY=https://goproxy.cn,direct

# 设置工作目录
WORKDIR /app

# 复制源代码（包含 go.mod）
COPY . .

# 下载安装依赖并生成 go.sum，然后构建
RUN go mod tidy && go build -o main .

# 暴露端口
EXPOSE 8080

# 运行应用
CMD ["./main"]