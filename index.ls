require! {
  util
  xml2js
  minimist
  'concat-stream'
  child_process: {spawn}
}

{_: [commitish]} = minimist process.argv[2 to]

git-log = spawn \git ['log' '--pretty=format:%H %P' commitish]

git-log.stdout.pipe concat-stream (log-buffer) ->
  log = log-buffer.to-string!

  commits = log.split '\n' .map (line, index) ->
    [hash, ...parents] = line.split ' '
    if parents.0 is ''
      parents = []
    {hash, parents, children: []}

  commit-hashes = Object.create null

  # Create reverse hash of commits by hash key
  for commit in commits
    commit-hashes[commit.hash] = commit

  # Caluculate children field for commits
  for commit in commits
    commit.parents .= map (parent-hash) -> commit-hashes[parent-hash]

    for parent in commit.parents
      parent.children.push commit

  # Abbreviate logs
  for commit, index in commits
    if commit.parents.length isnt 1
    or commit.children.length isnt 1
    or commit.parents.0.children.length isnt 1
    or commit.children.0.parents.length isnt 1
      continue

    parent = commit.parents.0
    child = commit.children.0

    parent.children = [child]
    child.parents = [parent]

    commits[index] = null

  commits .= filter (isnt null)

  for commit, index in commits
    commit.index = index

  svg = do
    svg:
      $:
        xmlns: 'http://www.w3.org/2000/svg'
        width: 1000
        height: commits.length * 50 + 60
      circle: []
      path: []
      text: []

  for commit in commits
    cx = 500
    cy = commit.index * 50 + 30
    svg.svg.circle.push $: {cx, cy, r: 15}

    x = cx + 30
    y = cy + 5
    svg.svg.text.push $: {x, y, font-size: 10}, _: commit.hash

    for parent in commit.parents
      parent-x = cx
      parent-y = parent.index * 50 + 30
      x1 = cx - (parent.index - commit.index) * 20
      y1 = (cy + parent-y) / 2

      d = "
        M #cx #cy
        Q #x1 #y1 #parent-x #parent-y
      "
      fill = \transparent
      stroke = \black
      stroke-width = 3

      svg.svg.path.push $: {d, fill, stroke, 'stroke-width': stroke-width}

  builder = new xml2js.Builder {+explicit-root}

  process.stdout.write builder.build-object svg
