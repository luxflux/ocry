# ocry

## Development
### Startup

```bash
INCOMING_PATH=tmp/incoming PDF_PATH=tmp/pdfs STORAGE_PATH=tmp/complete rackup -o 0.0.0.0 -P ocry.pid
```

### Start PDF merging

```bash
kill -USR1 $(cat ocry.pid)
```
