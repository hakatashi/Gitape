require! {
  util
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
