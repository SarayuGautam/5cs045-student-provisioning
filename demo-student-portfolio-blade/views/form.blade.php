@extends('layout')
@section('title', $project['id'] ? 'Edit project' : 'Add project')
@section('content')
<h1>{{ $project['id'] ? 'Edit project' : 'Add project' }}</h1>

@if ($errors)
    <div class="errors">
        <ul>
            @foreach ($errors as $e)
                <li>{{ $e }}</li>
            @endforeach
        </ul>
    </div>
@endif

<form method="post" action="project_save.php">
    <input type="hidden" name="csrf" value="{{ $csrf }}">
    <input type="hidden" name="id" value="{{ $project['id'] }}">

    <label for="title">Title</label>
    <input type="text" id="title" name="title" maxlength="120" value="{{ $project['title'] }}" required>

    <label for="description">Description</label>
    <textarea id="description" name="description" rows="5" required>{{ $project['description'] }}</textarea>

    <label for="tech">Technologies</label>
    <input type="text" id="tech" name="tech" maxlength="120" value="{{ $project['tech'] }}">

    <p><button type="submit">Save</button> <a href="index.php">Cancel</a></p>
</form>
@endsection
