<?php
declare(strict_types=1);

// Template only. The real file lives on the server at /etc/5cs045/smtp_config.php.
// Never put the real password in this file.
return [
    'host' => 'smtp.example.edu',
    'port' => 587,
    'username' => 'noreply@example.edu',
    'password' => 'CHANGE_ME',
    'from_address' => 'noreply@example.edu',
    'from_name' => 'Server Admin',
    'use_starttls' => true,
    'allowed_email_domain' => 'example.edu',
    // The students' websites, for the login email, and the sign-up page, for the link that confirms
    // a student's email. Emails always give a name: an IP address here is ignored, and without these
    // lines the two addresses below are used.
    'server_url' => 'https://fullstack-student.heraldcollege.edu.np',
    'signup_url' => 'https://fullstack.heraldcollege.edu.np',
    // Optional URL included in new admin credential emails. An IP address is ignored.
    'admin_panel_url' => 'https://fullstack.heraldcollege.edu.np:8443',
    // Where server alerts go (for example "disk 80% full"). Leave empty for no alerts.
    'admin_email' => '',
];
