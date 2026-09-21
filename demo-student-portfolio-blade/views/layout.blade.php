<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'My Portfolio')</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; color: #1f2937; }
        nav { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e5e7eb; padding-bottom: .75rem; margin-bottom: 1.5rem; }
        .card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; }
        .flash { background: #ecfdf5; border: 1px solid #a7f3d0; padding: .6rem 1rem; border-radius: 6px; margin-bottom: 1rem; }
        .errors { background: #fef2f2; border: 1px solid #fecaca; padding: .6rem 1rem; border-radius: 6px; margin-bottom: 1rem; }
        label { display: block; margin-top: .8rem; font-weight: 600; }
        input[type=text], input[type=password], textarea { width: 100%; padding: .5rem; box-sizing: border-box; }
        button, .btn { padding: .45rem .9rem; border: 0; border-radius: 6px; background: #1d4ed8; color: #fff; cursor: pointer; text-decoration: none; font-size: 1rem; }
        .danger { background: #b91c1c; }
        .muted { color: #6b7280; font-size: .9rem; }
        form.inline { display: inline; }
    </style>
</head>
<body>
<nav>
    <strong>My Portfolio</strong>
    <div>
        @if ($loggedIn)
            <span class="muted">{{ $username }}</span>
            <form class="inline" method="post" action="logout.php">
                <input type="hidden" name="csrf" value="{{ $csrf }}">
                <button type="submit">Log out</button>
            </form>
        @endif
    </div>
</nav>
@if ($flash)
    <div class="flash">{{ $flash }}</div>
@endif
@yield('content')
</body>
</html>
