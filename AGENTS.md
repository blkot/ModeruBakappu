# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

ModeruBakappu is a Python-based TUI application for managing LLM model backups between internal and external storage on macOS. The application detects installed LLM services (LM Studio, Omlx, Ollama), lists local models, and provides backup/restore functionality to manage limited drive space.

## Tech Stack

- **Language**: Python 3.9+
- **TUI Framework**: Textual (modern, async TUI library)
- **Platform**: macOS only
- **Storage**: File system operations with JSON configuration

## Project Structure

```
moderu_bakappu/
├── main.py                    # Application entry point and TUI interface
├── core/                      # Core functionality modules
│   ├── __init__.py
│   ├── llm_detector.py        # LLM service detection logic
│   └── model_manager.py       # Model operations (backup/restore/list)
├── requirements.txt           # Python dependencies
├── README.md                  # User documentation
└── AGENTS.md                  # This file
```

## Architecture

### Core Components

1. **LLMDetector** (`core/llm_detector.py`)
   - Detects installed LLM services by checking known storage paths
   - Service patterns for LM Studio, Omlx, and Ollama
   - Returns service information including model storage paths

2. **ModelManager** (`core/model_manager.py`)
   - Lists models from detected services (supports different storage patterns)
   - Handles model backup to external storage
   - Restores models from backup
   - Manages backup index and configuration
   - Calculates storage statistics

3. **TUI Interface** (`main.py`)
   - Textual-based terminal interface
   - Displays model lists with metadata
   - Provides backup/restore controls
   - Shows storage statistics

### LLM Service Storage Patterns

- **LM Studio**: `~/Library/Application Support/LM Studio/Models/` (recursive .gguf files)
- **Omlx**: `~/.ollx/models/` (directory-based model storage)
- **Ollama**: `~/.ollama/models/` (blob storage with manifest)

### Configuration Files

- **App Config**: `~/.moderu_bakappu/config.json` (backup path, preferences)
- **Backup Index**: `~/.moderu_bakappu/backup_index.json` (tracks backed up models)

## Development Commands

### Installation
```bash
# Install dependencies
pip install -r requirements.txt
```

### Running the Application
```bash
# Run the TUI application
python main.py
```

### Development
```bash
# Run with verbose output for debugging
python main.py --debug

# Test specific components
python -m core.llm_detector
python -m core.model_manager
```

## Key Design Decisions

1. **Service Pattern System**: LLM services use different storage patterns (GGUF files, directories, blobs). The `llm_detector.py` uses a pattern-based approach to handle different storage structures.

2. **Model Identification**: Models are identified using `service_id:model_name` format to avoid conflicts between services with similarly named models.

3. **Backup Index**: JSON-based tracking system maintains the relationship between original paths and backup locations, enabling restoration without service-specific logic.

4. **Error Handling**: File operations are wrapped in try-except blocks to handle permission issues, missing files, and other filesystem errors gracefully.

## Extension Points

### Adding New LLM Services

To add support for a new LLM service:

1. Add service configuration to `SERVICE_PATTERNS` in `core/llm_detector.py`
2. Implement storage pattern detection method in `ModelManager`
3. Update model discovery logic if service uses unique storage format

### Improving TUI

The TUI is built with Textual framework. Key areas for enhancement:
- Model filtering and search
- Batch operations (multiple selection)
- Progress bars for large file operations
- Better error display and handling
- Configuration interface within TUI

## macOS-Specific Considerations

- Application support directory: `~/Library/Application Support/`
- Hidden config directory: `~/.moderu_bakappu/`
- External drive mounting: `/Volumes/`
- File system case sensitivity: macOS is case-insensitive by default
- Permission handling: Some model directories may require elevated permissions

## Common Patterns

### Error Handling
Always wrap filesystem operations in try-except blocks to handle `OSError`, `IOError`, and `shutil.Error` exceptions.

### Path Operations
Use `pathlib.Path` for all path operations instead of string manipulation. This ensures cross-platform compatibility and better error handling.

### Configuration Management
User-specific configuration is stored in `~/.moderu_bakappu/`. Create this directory if it doesn't exist on startup.

### Model Discovery
Different services use different patterns. The `pattern` field in service configuration determines which discovery method to use:
- `recursive_gguf`: Search recursively for .gguf files
- `directory_based`: Each subdirectory is a model
- `blob_storage`: Complex blob storage (requires manifest parsing)

## Future Enhancement Ideas

1. **Automatic Service Detection**: Monitor filesystem for new LLM service installations
2. **Smart Backup Suggestions**: Suggest models to backup based on usage patterns
3. **Compression**: Optional compression for backup storage
4. **Cloud Integration**: Support cloud storage backends
5. **Scheduled Backups**: Automatic backup operations
6. **Model Metadata**: Extract and display model parameters, quantization, etc.