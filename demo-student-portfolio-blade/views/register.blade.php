@extends('layout')
@section('title', 'Create account')
@section('content')
<h1>Create account</h1>
@if ($errors)
    <div class="errors">
        <ul>
            @foreach ($errors as $e)
                <li>{{ $e }}</li>
            @endforeach
        </ul>
    </div>
@endif
<form method="post" action="register.php">
    <input type="hidden" name="csrf" value="{{ $csrf }}">
    <label for="username">Username</label>
    <input type="text" id="username" name="username" value="{{ $username }}" required>
    <label for="password">Password (min 8 characters)</label>
    <input type="password" id="password" name="password" required>
    <p><button type="submit">Create account</button></p>
</form>
<p class="muted"><a href="login.php">Back to log in</a></p>
@endsection
