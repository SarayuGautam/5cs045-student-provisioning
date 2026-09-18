<?php
/**
 * smtp_mailer.php — minimal SMTP client (STARTTLS + AUTH LOGIN), no external
 * dependencies. Handles exactly what the registration handler needs: send
 * one plain-text email through an authenticated relay.
 *
 * Why not PHPMailer: it's the more common choice and perfectly reasonable
 * if you'd rather use it — but it needs `composer require phpmailer/phpmailer`,
 * which needs the box to reach repo.packagist.org. Rather than hand you an
 * integration I couldn't verify end-to-end, this is ~120 lines of plain
 * SMTP protocol I could actually test against a real server (see
 * test/smoke-test-email.php). Swap to PHPMailer later if you prefer — the
 * one call site in register_handler.php is easy to replace.
 */
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
        // Test-only: trust this specific CA file in addition to the system
        // store. Leave null in production — a real SMTP relay has a
        // properly-chained cert and needs no special handling. This exists
        // solely so I can test the STARTTLS path against my own self-signed
        // test server without weakening verification generally (it does NOT
        // disable hostname or chain checks).
        private ?string $testCaFile = null,
    ) {}

    private function buildStreamContext() {
        $opts = ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true]];
        if ($this->testCaFile !== null) {
            $opts['ssl']['cafile'] = $this->testCaFile;
        }
        return stream_context_create($opts);
    }

    /** @throws RuntimeException on any SMTP-level failure */
    public function send(string $toAddress, string $subject, string $body): void {
        $sock = @stream_socket_client(
            "tcp://{$this->host}:{$this->port}", $errno, $errstr,
            $this->timeoutSeconds, STREAM_CLIENT_CONNECT, $this->buildStreamContext()
        );
        if ($sock === false) {
            throw new RuntimeException("Could not connect to {$this->host}:{$this->port} — {$errstr} ({$errno})");
        }
        stream_set_timeout($sock, $this->timeoutSeconds);

        try {
            $this->expect($sock, 220, 'connect');
            $this->command($sock, "EHLO 5cs045-student-server", 250);

            if ($this->useStartTls) {
                $this->command($sock, "STARTTLS", 220);
                if (!stream_socket_enable_crypto($sock, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                    throw new RuntimeException("STARTTLS negotiation failed");
                }
                // Capabilities must be re-negotiated after the TLS upgrade (RFC 3207).
                $this->command($sock, "EHLO 5cs045-student-server", 250);
            }

            if ($this->username !== '') {
                $this->command($sock, "AUTH LOGIN", 334);
                $this->command($sock, base64_encode($this->username), 334);
                $this->command($sock, base64_encode($this->password), 235);
            }

            $this->command($sock, "MAIL FROM:<{$this->fromAddress}>", 250);
            $this->command($sock, "RCPT TO:<{$toAddress}>", 250);
            $this->command($sock, "DATA", 354);

            $headers = [
                "From: {$this->fromName} <{$this->fromAddress}>",
                "To: <{$toAddress}>",
                "Subject: {$subject}",
                "Date: " . date('r'),
                "Message-ID: <" . bin2hex(random_bytes(12)) . "@5cs045-student-server>",
                "Content-Type: text/plain; charset=UTF-8",
                "MIME-Version: 1.0",
            ];
            // Dot-stuffing (RFC 5321 4.5.2): any line starting with "." gets an
            // extra "." prepended, or a lone "." on a line would be read as
            // end-of-DATA by the server.
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

    private function expect($sock, int $expectCode, string $context): string {
        return $this->readResponse($sock, $expectCode, $context);
    }

    /**
     * Reads one full SMTP response, correctly handling multi-line replies
     * (RFC 5321: "250-text" continues, "250 text" or "250" ends the reply —
     * the 4th character is '-' for a continuation line, ' ' or end-of-line
     * for the final line).
     */
    private function readResponse($sock, int $expectCode, string $context): string {
        $full = '';
        do {
            $line = fgets($sock, 1024);
            if ($line === false) {
                throw new RuntimeException("Connection closed while waiting for a response to: {$context}");
            }
            $full .= $line;
            $continues = (strlen($line) >= 4 && $line[3] === '-');
        } while ($continues);

        $code = (int) substr($full, 0, 3);
        if ($code !== $expectCode) {
            throw new RuntimeException("SMTP error after '{$context}': expected {$expectCode}, got: " . trim($full));
        }
        return $full;
    }
}
