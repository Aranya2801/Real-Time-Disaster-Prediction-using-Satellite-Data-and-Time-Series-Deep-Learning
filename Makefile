# =============================================================================
# Real-Time Disaster Prediction Platform — Makefile
# =============================================================================

.PHONY: all install dev-install frontend-install test lint format
.PHONY: train predict api dashboard docker-up docker-down
.PHONY: data-generate data-download mlflow grafana clean help

PYTHON   := python3
PIP      := pip3
NODE     := node
NPM      := npm
DOCKER   := docker
DC       := docker-compose -f docker/docker-compose.yml

# ── Setup ──────────────────────────────────────────────────────────────────────
all: install

install:
	$(PIP) install -r requirements.txt
	@echo "✅ Python dependencies installed"

dev-install:
	$(PIP) install -r requirements.txt
	$(PIP) install ruff black isort mypy pytest pytest-cov pre-commit
	pre-commit install
	@echo "✅ Dev dependencies installed"

frontend-install:
	cd frontend && $(NPM) install
	@echo "✅ Frontend dependencies installed"

# ── Testing ────────────────────────────────────────────────────────────────────
test:
	pytest tests/ -v --cov=ml --cov=backend --cov-report=term-missing

test-ml:
	pytest tests/unit/test_models.py -v

test-api:
	pytest tests/unit/test_api.py -v

test-fast:
	pytest tests/ -v -m "not slow and not integration"

test-all:
	pytest tests/ -v --cov=ml --cov=backend --cov=agents --cov-report=html

# ── Code Quality ───────────────────────────────────────────────────────────────
lint:
	ruff check ml/ backend/ agents/ tests/
	@echo "✅ Lint passed"

format:
	black ml/ backend/ agents/ tests/
	isort ml/ backend/ agents/ tests/
	@echo "✅ Formatted"

type-check:
	mypy ml/ backend/ --ignore-missing-imports
	@echo "✅ Type check passed"

# ── Data ───────────────────────────────────────────────────────────────────────
data-generate:
	$(PYTHON) datasets/dataset_registry.py
	@echo "✅ Synthetic dataset generated in datasets/synthetic/"

data-download-firms:
	$(PYTHON) scripts/download_firms.py --days 7
	@echo "✅ NASA FIRMS data downloaded"

data-download-era5:
	$(PYTHON) scripts/download_era5.py --year 2023 --vars temperature precipitation
	@echo "✅ ERA5 data downloaded"

# ── Training ───────────────────────────────────────────────────────────────────
train-flood:
	$(PYTHON) ml/training/trainer.py --model flood --epochs 100 --d-model 256
	@echo "✅ Flood model training complete"

train-wildfire:
	$(PYTHON) ml/training/trainer.py --model wildfire --epochs 100
	@echo "✅ Wildfire model training complete"

train-fusion:
	$(PYTHON) ml/training/trainer.py --model fusion --epochs 100 --d-model 256
	@echo "✅ Fusion model training complete"

train-rl:
	$(PYTHON) -c "
from ml.models.fusion.rl_resource_allocation import DisasterResponseEnv, DisasterResponsePolicy, PPOTrainer
env = DisasterResponseEnv()
policy = DisasterResponsePolicy()
trainer = PPOTrainer(env, policy)
result = trainer.train(total_steps=100000)
print('RL training:', result)
"
	@echo "✅ RL resource allocation trained"

train-all: train-flood train-wildfire train-fusion
	@echo "✅ All models trained"

# ── Services ───────────────────────────────────────────────────────────────────
api:
	uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload --log-level info

api-prod:
	uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --workers 4

dashboard:
	cd frontend && $(NPM) run dev

agents:
	$(PYTHON) -c "
import asyncio
from agents.multi_agent_system import DisasterAgentSystem
system = DisasterAgentSystem()
asyncio.run(system.start_all())
"

mlflow:
	mlflow server --host 0.0.0.0 --port 5000 \
		--backend-store-uri sqlite:///mlflow.db \
		--default-artifact-root ./models/artifacts
	@echo "MLflow at http://localhost:5000"

# ── Docker ─────────────────────────────────────────────────────────────────────
docker-build:
	$(DOCKER) build -f docker/Dockerfile.api -t disaster-api:latest .
	$(DOCKER) build -f docker/Dockerfile.frontend -t disaster-frontend:latest ./frontend

docker-up:
	$(DC) up -d
	@echo "✅ All services started"
	@echo "  API:       http://localhost:8000/api/docs"
	@echo "  Dashboard: http://localhost:3000"
	@echo "  MLflow:    http://localhost:5000"
	@echo "  Grafana:   http://localhost:3001"
	@echo "  Prometheus:http://localhost:9090"

docker-down:
	$(DC) down

docker-logs:
	$(DC) logs -f api

docker-restart:
	$(DC) restart api

# ── Kubernetes ─────────────────────────────────────────────────────────────────
k8s-deploy:
	kubectl apply -f kubernetes/ -n disaster-platform
	@echo "✅ Kubernetes deployment applied"

k8s-status:
	kubectl get all -n disaster-platform

k8s-logs:
	kubectl logs -f deployment/disaster-api -n disaster-platform

# ── Monitoring ─────────────────────────────────────────────────────────────────
grafana:
	@echo "Grafana: http://localhost:3001 (admin/admin123)"

prometheus:
	@echo "Prometheus: http://localhost:9090"

# ── Utilities ──────────────────────────────────────────────────────────────────
init-dirs:
	mkdir -p datasets/raw datasets/processed datasets/synthetic
	mkdir -p models/checkpoints models/artifacts models/registry
	mkdir -p logs reports
	@echo "✅ Directories created"

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete
	find . -name "*.pyo" -delete
	rm -rf .pytest_cache htmlcov .coverage
	@echo "✅ Cleaned"

clean-all: clean
	rm -rf models/checkpoints/* logs/*
	@echo "✅ Full clean done"

# ── Help ───────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║   Real-Time Disaster Prediction Platform — Commands      ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  Setup:"
	@echo "    make install           — Install Python deps"
	@echo "    make dev-install       — Install + dev tools"
	@echo "    make frontend-install  — Install Node.js deps"
	@echo ""
	@echo "  Data:"
	@echo "    make data-generate     — Generate synthetic dataset"
	@echo "    make data-download-firms — Download NASA FIRMS"
	@echo "    make data-download-era5  — Download ERA5 climate"
	@echo ""
	@echo "  Training:"
	@echo "    make train-flood       — Train flood model"
	@echo "    make train-wildfire    — Train wildfire model"
	@echo "    make train-fusion      — Train fusion model"
	@echo "    make train-all         — Train all models"
	@echo ""
	@echo "  Services:"
	@echo "    make api               — Start FastAPI (dev)"
	@echo "    make dashboard         — Start Next.js dashboard"
	@echo "    make agents            — Start multi-agent system"
	@echo "    make mlflow            — Start MLflow server"
	@echo ""
	@echo "  Docker:"
	@echo "    make docker-up         — Start all services"
	@echo "    make docker-down       — Stop all services"
	@echo ""
	@echo "  Testing:"
	@echo "    make test              — Run all tests"
	@echo "    make lint              — Run linter"
	@echo "    make format            — Format code"
	@echo ""
