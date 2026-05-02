# N-Bus Power Flow Studio

MATLAB toolkit for power system analysis — Newton-Raphson, Gauss-Seidel, Continuation Power Flow (CPF), Optimal Power Flow (OPF), and AI-assisted analysis.

## Features

- **Power Flow Solvers**: Newton-Raphson and Gauss-Seidel with Q-limit enforcement
- **Continuation Power Flow**: Load scaling and predictor-corrector methods for voltage stability
- **Economic Dispatch / OPF**: Classical quadratic-cost optimization with generator limits
- **AI Analysis Service**: FastAPI + LLM integration for automated result interpretation
- **Modern MATLAB GUI**: Theme-switchable web-app-inspired interface
- **Multi-format Export**: CSV, JSON, HTML, PDF, PNG
- **Benchmark Mode**: Headless multi-method comparison with timing
- **Test Suite**: MATLAB unit tests + Python pytest for AI service

## Quick Start

### MATLAB GUI

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
run_powerflow_gui
```

### AI Service

```bash
cd ai_service
cp .env.example .env   # edit with your API key
pip install -r requirements.txt
python server.py
```

### Docker

```bash
cd ai_service
docker compose up -d
```

### Headless Benchmark

```matlab
pf_init_paths();
results = benchmark_all_methods(case_ieee5bus());
```

## Project Structure

```
n_bus_clone/
├── +pfapp/              # GUI application package
│   ├── run_powerflow_gui.m       # GUI launcher
│   ├── create_gui_layout.m       # Modern themed layout
│   ├── run_selected_action.m     # Solver dispatch
│   ├── export_json_action.m      # JSON export
│   ├── export_html_action.m      # HTML report export
│   ├── build_html_report.m       # HTML report generator
│   ├── toggle_theme.m            # Light/dark theme
│   ├── save_preferences.m        # Persist user settings
│   ├── load_preferences.m        # Restore user settings
│   ├── discover_cases.m          # Auto-scan +cases/
│   ├── run_async_action.m        # Async solver (PCT)
│   ├── run_tests_action.m        # Test runner
│   └── thai_messages.m           # Thai localization
├── +pfsolver/           # Power flow solvers
│   ├── powerflow_newton_raphson.m
│   ├── powerflow_gauss_seidel.m
│   ├── cpf_load_scaling.m
│   ├── cpf_predictor_corrector.m
│   ├── economic_dispatch_opf.m
│   ├── ac_optimal_power_flow.m
│   └── benchmark_all_methods.m   # Headless benchmark
├── +cases/              # IEEE/Saadat test cases
├── +ai_client/          # MATLAB client for AI service
├── ai_service/          # FastAPI AI analysis service
│   ├── server.py                 # Main server
│   ├── config.py                 # Configuration
│   ├── models.py                 # Pydantic models
│   ├── prompts.py                # LLM prompts
│   ├── utils.py                  # Utilities
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── tests/                    # Python tests
├── internal/            # Shared internal utilities
│   ├── pf_export_*.m            # Export functions
│   └── plotting/                # Plotting functions
├── tests/               # MATLAB unit tests
│   ├── test_nr_solver.m
│   ├── test_gs_solver.m
│   ├── test_cpf.m
│   └── test_opf.m
├── .github/workflows/   # CI/CD
│   └── ci.yml
└── output/              # Generated reports and plots
```

## AI Service API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check + API status |
| GET | `/metrics` | Prometheus metrics |
| POST | `/analyze` | Analyze power flow results |
| POST | `/analyze/cpf` | Analyze CPF results |
| POST | `/analyze/opf` | Analyze OPF results |
| POST | `/compare` | Compare two solvers |
| POST | `/report` | Generate comprehensive report |
| POST | `/ask` | Free-form Q&A with history |
| POST | `/ask/stream` | Streaming SSE response |

## Configuration

### AI Service (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_API_KEY` | *required* | DeepSeek/OpenAI API key |
| `LLM_BASE_URL` | `https://api.deepseek.com` | API base URL |
| `LLM_MODEL` | `deepseek-v4-flash` | Model name |
| `API_AUTH_TOKEN` | (empty) | Bearer token for auth |
| `PORT` | `8000` | Server port |
| `MAX_TOKENS` | `4096` | Max response tokens |
| `RATE_LIMIT_REQUESTS` | `30` | Rate limit per window |
| `RATE_LIMIT_WINDOW_SEC` | `60` | Rate limit window |

## Test Cases

| Case | Buses | Method | Source |
|------|-------|--------|--------|
| IEEE 5-bus | 5 | PF, CPF | Saadat Ch.6 |
| IEEE 14-bus | 14 | PF, CPF | MATPOWER |
| IEEE 30-bus | 30 | PF, CPF, OPF | Saadat/MATPOWER |
| IEEE 300-bus | 300 | PF | MATPOWER |
| Saadat 3-bus PQ | 3 | PF | Saadat Ex 6.7 |
| Saadat 3-bus PV | 3 | PF | Saadat Ex 6.8 |
| Saadat OPF Ex 7.4-7.6 | var | OPF | Saadat Ch.7 |

## Running Tests

### MATLAB
```matlab
import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
suite = TestSuite.fromFolder('tests');
runner = TestRunner.withTextOutput();
runner.run(suite);
```

### Python
```bash
cd ai_service
pip install pytest pytest-asyncio httpx
python -m pytest tests/ -v
```

## License

MIT
