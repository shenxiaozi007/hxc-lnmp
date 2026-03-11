package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/mux"
)

var db *sql.DB

func main() {
	// 数据库连接配置
	dbHost := getEnv("DB_HOST", "mysql")
	dbPort := getEnv("DB_PORT", "3306")
	dbName := getEnv("DB_NAME", "app_db")
	dbUser := getEnv("DB_USER", "app_user")
	dbPassword := getEnv("DB_PASSWORD", "userpassword")

	// 连接数据库
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s", dbUser, dbPassword, dbHost, dbPort, dbName)
	var err error
	db, err = sql.Open("mysql", dsn)
	if err != nil {
		log.Fatal("数据库连接失败:", err)
	}
	defer db.Close()

	// 测试数据库连接
	err = db.Ping()
	if err != nil {
		log.Fatal("数据库连接测试失败:", err)
	}

	// 创建路由
	r := mux.NewRouter()

	// 路由配置
	r.HandleFunc("/", homeHandler).Methods("GET")
	r.HandleFunc("/health", healthHandler).Methods("GET")
	r.HandleFunc("/api/data", dataHandler).Methods("GET")

	// 启动服务器
	log.Println("Go应用服务启动在端口 8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "欢迎使用LNMP环境 - Go应用服务正常运行!")
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	// 检查数据库连接
	err := db.Ping()
	if err != nil {
		http.Error(w, "数据库连接异常", http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "服务状态: 正常")
}

func dataHandler(w http.ResponseWriter, r *http.Request) {
	// 示例数据库查询
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM information_schema.tables").Scan(&count)
	if err != nil {
		http.Error(w, "数据库查询失败", http.StatusInternalServerError)
		return
	}

	fmt.Fprintf(w, "数据库表数量: %d", count)
}
