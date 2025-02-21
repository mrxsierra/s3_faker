$dockerPath = Resolve-Path "C:\Program Files*\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
if ($dockerPath) {
    & $dockerPath
} else {
    Write-Warning "Docker Desktop not found. Please check the installation path."
}

$current_dir = $(pwd)
echo $current_dir

Start-Process powershell -ArgumentList "-NoExit", "-c", "cd $current_dir; ls; localstack start; exit"
powershell -c "awslocal --endpoint-url=http://localhost:4566 s3 mb s3://mamoke-bucket; awslocal s3 ls; python app.py; localstack stop;"
