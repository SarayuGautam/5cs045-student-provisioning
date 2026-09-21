@extends('layout')
@section('title', 'Log in')
@section('content')
<h1>Log in</h1>
@if ($error)
    <div class="errors">{{ $error }}</div>
@endif
<form method="post" action="login.php">
    <input type="hidden" name="csrf" value="{{ $csrf }}">
    <label for="username">Username</label>
    <input type="text" id="username" name="username" required>
    <label for="password">Password</label>
    <input type="password" id="password" name="password" required>
    <p><button type="submit">Log in</button></p>
</form>
<p class="muted">No account? <a href="register.php">Create one</a>.</p>
@endsection
