[[Task inbox]]

> [!warning] Due Today
> ```tasks
> not done
> due today
> sort by priority
> hide toolbar
hide task count
> ```

> [!info] Upcoming (Next 7 Days)
> ```tasks
> not done
> due before in 7 days
> sort by due
> hide toolbar
hide task count
> ```

## Work

> [!work] Active Work Tasks
> ```tasks
> not done
> tag includes #work
> tag does not include #waiting
> sort by due
> hide toolbar
hide task count
> ```

> [!work]- Recently Completed Work
> ```tasks
> done
> tag includes #work
> done after 7 days ago
> sort by done reverse
> hide toolbar
hide task count
> ```
### Waiting on others
```tasks
not done
tag includes #waiting
sort by due
group by function task.description.match(/\[\[People\/[^\]]+\]\]/)?.[0] || "Unassigned"
hide toolbar
hide task count
```
## Personal

> [!personal] Active Personal Tasks
> ```tasks
> not done
> tag includes #personal
> tag does not include #waiting
> sort by due
> hide toolbar
hide task count
> ```

> [!personal]- Recently Completed Personal
> ```tasks
> done
> tag includes #personal
> done after 7 days ago
> sort by done reverse
> hide toolbar
hide task count
> ```
