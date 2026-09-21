@extends('layout')
@section('title', 'My Projects')
@section('content')
<h1>My projects</h1>
<p><a class="btn" href="project_form.php">Add project</a></p>

<label for="search">Search by title or technology</label>
<input type="text" id="search" placeholder="Type to search..." autocomplete="off">

<div id="results" style="margin-top:1rem">
    @forelse ($projects as $p)
        <div class="card">
            <h3>{{ $p['title'] }}</h3>
            <p>{{ $p['description'] }}</p>
            <p class="muted">{{ $p['tech'] }}</p>
            <a class="btn" href="project_form.php?id={{ $p['id'] }}">Edit</a>
            <form class="inline" method="post" action="project_delete.php" onsubmit="return confirm('Delete this project?')">
                <input type="hidden" name="csrf" value="{{ $csrf }}">
                <input type="hidden" name="id" value="{{ $p['id'] }}">
                <button class="danger" type="submit">Delete</button>
            </form>
        </div>
    @empty
        <p class="muted">No projects yet.</p>
    @endforelse
</div>

<script>
// Ajax search with the Fetch API. Results are built with textContent (not
// innerHTML) so project text can never inject HTML or scripts into the page.
const box = document.getElementById('search');
const results = document.getElementById('results');
let timer;

box.addEventListener('input', () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
        const res = await fetch('search.php?q=' + encodeURIComponent(box.value));
        if (!res.ok) { results.textContent = 'Search failed.'; return; }
        const rows = await res.json();
        results.replaceChildren();
        if (rows.length === 0) {
            const p = document.createElement('p');
            p.className = 'muted';
            p.textContent = 'No matching projects.';
            results.append(p);
            return;
        }
        for (const r of rows) {
            const card = document.createElement('div');
            card.className = 'card';
            const h = document.createElement('h3'); h.textContent = r.title;
            const d = document.createElement('p');  d.textContent = r.description;
            const t = document.createElement('p');  t.className = 'muted'; t.textContent = r.tech;
            const a = document.createElement('a');  a.className = 'btn'; a.textContent = 'Edit';
            a.href = 'project_form.php?id=' + encodeURIComponent(r.id);
            card.append(h, d, t, a);
            results.append(card);
        }
    }, 250);
});
</script>
@endsection
