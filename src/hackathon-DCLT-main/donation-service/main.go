package main
 
import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
 
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
 
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)
 
type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}
 
type App struct {
	DB          *sql.DB
	SqsSvc      *sqs.SQS
	SqsQueueURL string
}
 
// initTracer configura o exportador OTLP para o New Relic.
// Lê OTEL_EXPORTER_OTLP_ENDPOINT e OTEL_EXPORTER_OTLP_HEADERS do ambiente.
// Retorna uma função de shutdown para flush dos spans pendentes.
func initTracer(ctx context.Context) (func(context.Context) error, error) {
	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "donation-service"
	}
 
	// Cria o exportador OTLP via gRPC.
	// O SDK do OTel lê automaticamente OTEL_EXPORTER_OTLP_ENDPOINT e
	// OTEL_EXPORTER_OTLP_HEADERS das variáveis de ambiente.
	exporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, err
	}
 
	// Resource: atributos que identificam o serviço no APM.
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceNamespace("solidarytech"),
			semconv.DeploymentEnvironment(os.Getenv("ENVIRONMENT")),
		),
	)
	if err != nil {
		return nil, err
	}
 
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
 
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))
 
	log.Printf("OpenTelemetry inicializado — serviço: %s", serviceName)
	return tp.Shutdown, nil
}
 
func main() {
	_ = godotenv.Load()
 
	ctx := context.Background()
 
	// Inicializa o tracer OTel antes de qualquer coisa.
	// Se falhar, o serviço continua funcionando sem instrumentação.
	shutdown, err := initTracer(ctx)
	if err != nil {
		log.Printf("Aviso: falha ao inicializar OpenTelemetry: %v", err)
	} else {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := shutdown(shutdownCtx); err != nil {
				log.Printf("Erro no shutdown do OTel: %v", err)
			}
		}()
	}
 
	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}
 
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}
 
	db, err := sql.Open("pgx", dbURL)
	if err != nil || db.Ping() != nil {
		log.Fatalf("Erro ao conectar ao banco de dados: %v", err)
	}
	log.Println("Conectado ao PostgreSQL (donation-service).")
 
	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
		sqsSvc = sqs.New(sess)
		log.Println("Integração com AWS SQS ativada.")
	}
 
	app := &App{DB: db, SqsSvc: sqsSvc, SqsQueueURL: queueURL}
 
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)
 
	// otelhttp envolve o mux para gerar spans automáticos em cada request HTTP.
	// Isso substitui o mux original — todas as rotas ganham instrumentação.
	handler := otelhttp.NewHandler(mux, "donation-service",
		otelhttp.WithSpanNameFormatter(func(op string, r *http.Request) string {
			return r.Method + " " + r.URL.Path
		}),
	)
 
	server := &http.Server{
		Addr:    ":" + port,
		Handler: handler,
	}
 
	// Graceful shutdown para garantir flush dos spans antes de sair.
	go func() {
		log.Printf("donation-service rodando na porta %s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Erro ao iniciar servidor: %v", err)
		}
	}()
 
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
 
	log.Println("Encerrando donation-service...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("Erro no shutdown do servidor: %v", err)
	}
}
 
func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}
 
func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	ctx := r.Context()
 
	// Span customizado para a operação de negócio.
	// O span pai (HTTP request) é criado automaticamente pelo otelhttp.NewHandler.
	tracer := otel.Tracer("donation-service")
 
	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}
 
		d.Status = "APPROVED" // Simulação de gateway de pagamento
 
		// Span filho para o INSERT no banco — aparece como span aninhado no trace.
		_, insertSpan := tracer.Start(ctx, "db.insert_donation")
		insertSpan.SetAttributes(
			attribute.Int("donation.ngo_id", d.NgoID),
			attribute.Float64("donation.amount", d.Amount),
		)
 
		err := a.DB.QueryRow(
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)
		insertSpan.End()
 
		if err != nil {
			log.Printf("Erro ao salvar doação: %v", err)
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
 
		if a.SqsSvc != nil {
			go a.sendNotificationEvent(d)
		}
 
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(d)
		return
	}
 
	if r.Method == http.MethodGet {
		rows, err := a.DB.Query("SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()
 
		donations := []Donation{}
		for rows.Next() {
			var d Donation
			rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}
 
		json.NewEncoder(w).Encode(donations)
		return
	}
 
	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}
 
func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	_, err := a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(a.SqsQueueURL),
	})
	if err != nil {
		log.Printf("Falha ao despachar evento SQS: %v", err)
	}
}
 