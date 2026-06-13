# terraform_setup.ps1

# 기본 설정 (사용자 환경에 맞게 변경)
$PRD_ASSUME_ROLE_ARN = "arn:aws:iam::564290535730:role/terraformRole"
$SESSION_NAME = "chopha66@gmail.com"

$AWS_OPS = @()
$ASSUME_ROLE_ARN = ""

function help {
    Write-Host @"
usage: .\terraform_setup.ps1

  -profile <name>   AWS profile name
  -setup            Setup temporary AWS key pair (-p for Production)
  -clean            Clean up environment variables
"@
}

function setupCredentials {
    Write-Host "Fetching AWS STS credentials..."

    # AWS STS 명령어 실행 및 JSON 결과 파싱
    # @AWS_OPS 배열을 인자로 전달하여 프로필 적용
    $rawOutput = aws sts @AWS_OPS assume-role --role-arn $ASSUME_ROLE_ARN --role-session-name $SESSION_NAME | ConvertFrom-Json

    if (-not $rawOutput.Credentials) {
        Write-Error "Failed to assume role. Please check your AWS profile or permissions."
        exit 1
    }

    $awsKeyId = $rawOutput.Credentials.AccessKeyId
    $awsSecretKey = $rawOutput.Credentials.SecretAccessKey
    $sessionToken = $rawOutput.Credentials.SessionToken

    # PowerShell 프로세스 레벨 환경 변수 설정 (현재 창에만 적용)
    $env:AWS_ACCESS_KEY_ID = $awsKeyId
    $env:AWS_SECRET_ACCESS_KEY = $awsSecretKey
    $env:AWS_SESSION_TOKEN = $sessionToken

    Write-Host "`n[Success] AWS Credentials environment variables set!" -ForegroundColor Green
    Write-Host "AWS_ACCESS_KEY_ID = $awsKeyId"
    Write-Host "AWS_SECRET_ACCESS_KEY = (Hidden)"
    Write-Host "AWS_SESSION_TOKEN = (Hidden)"
}

function cleanCredentials {
    # 환경 변수 초기화
    Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
    Write-Host "AWS environment variables cleared." -ForegroundColor Yellow
}

# 파라미터(인자) 처리 루프
$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        "-help" {
            help
            exit 1
        }
        "-profile" {
            $i++
            if ($i -lt $args.Count) {
                $AWS_OPS = @("--profile", $args[$i])
            }
        }
        "-setup" {
            # 다음 인자가 생산계(-p) 옵션인지 확인
            if (($i + 1) -lt $args.Count -and $args[$i + 1] -eq "-p") {
                $i++
                $ASSUME_ROLE_ARN = $PRD_ASSUME_ROLE_ARN
            } else {
                # 기본 Role ARN이 비어있다면 에러 처리 혹은 기본값 지정 필요
                if (-not $ASSUME_ROLE_ARN) { $ASSUME_ROLE_ARN = $PRD_ASSUME_ROLE_ARN }
            }
            setupCredentials
            exit 0
        }
        "-clean" {
            cleanCredentials
            exit 0
        }
        Default {
            help
            exit 1
        }
    }
    $i++
}