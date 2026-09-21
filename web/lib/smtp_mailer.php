<?php
declare(strict_types=1);

final class SmtpMailer {
    public function __construct(
        private string $host,
        private int $port,
        private string $username,
        private string $password,
        private string $fromAddress,
        private string $fromName = '5CS045 Student Server',
        private bool $useStartTls = true,
        private int $timeoutSeconds = 15,
    ) {}

    public function send(string $toAddress, string $subject, string $body): void {
        $sock = @stream_socket_client(
            "tcp://{$this->host}:{$this->port}", $errno, $errstr,
            $this->timeoutSeconds, STREAM_CLIENT_CONNECT,
            stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true]])
        );
        if ($sock === false) {
            throw new RuntimeException("Could not connect to {$this->host}:{$this->port} - {$errstr} ({$errno})");
        }
        stream_set_timeout($sock, $this->timeoutSeconds);
        try {
            $this->readResponse($sock, 220, 'connect');
            $this->command($sock, 'EHLO 5cs045-student-server', 250);
            if ($this->useStartTls) {
                $this->command($sock, 'STARTTLS', 220);
                if (!stream_socket_enable_crypto($sock, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                    throw new RuntimeException('STARTTLS negotiation failed');
                }
                $this->command($sock, 'EHLO 5cs045-student-server', 250);
            }
            if ($this->username !== '') {
                $this->command($sock, 'AUTH LOGIN', 334);
                $this->command($sock, base64_encode($this->username), 334);
                $this->command($sock, base64_encode($this->password), 235);
            }
            $this->command($sock, "MAIL FROM:<{$this->fromAddress}>", 250);
            $this->command($sock, "RCPT TO:<{$toAddress}>", 250);
            $this->command($sock, 'DATA', 354);
            $headers = [
                "From: {$this->fromName} <{$this->fromAddress}>",
                "To: <{$toAddress}>",
                "Subject: {$subject}",
                'Date: ' . date('r'),
                'Message-ID: <' . bin2hex(random_bytes(12)) . '@5cs045-student-server>',
                'Content-Type: text/plain; charset=UTF-8',
                'MIME-Version: 1.0',
            ];
            $stuffedBody = preg_replace('/^\./m', '..', $body);
            $message = implode("\r\n", $headers) . "\r\n\r\n" . $stuffedBody . "\r\n.\r\n";
            fwrite($sock, $message);
            $this->readResponse($sock, 250, 'DATA body');
            fwrite($sock, "QUIT\r\n");
        } finally {
            fclose($sock);
        }
    }

    private function command($sock, string $line, int $expectCode): string {
        fwrite($sock, $line . "\r\n");
        return $this->readResponse($sock, $expectCode, $line);
    }

    private function readResponse($sock, int $expectCode, string $context): string {
        $full = '';
        do {
            $line = fgets($sock, 1024);
            if ($line === false) {
                throw new RuntimeException("Connection closed while waiting for a response to: {$context}");
            }
            $full .= $line;
            $continues = strlen($line) >= 4 && $line[3] === '-';
        } while ($continues);
        $code = (int) substr($full, 0, 3);
        if ($code !== $expectCode) {
            throw new RuntimeException("SMTP error after '{$context}': expected {$expectCode}, got: " . trim($full));
        }
        return $full;
    }
}
