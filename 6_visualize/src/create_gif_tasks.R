# create task tables for gif generation

create_timestep_gif_tasks <- function(timestep_ind, folders){

  # prepare a data.frame with one row per task
  timesteps <- readRDS(sc_retrieve(timestep_ind, '2_process.yml'))
  tasks <- data_frame(timestep=timesteps) %>%
    mutate(task_name = strftime(timestep, format = '%Y%m%d_%H', tz = 'UTC'))

  # ---- timestep-specific png plotting layers ---- #

  datewheel <- scipiper::create_task_step(
    step_name = 'datewheel',
    target_name = function(task_name, step_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      sprintf('datewheel_fun_%s', task_name)
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      sprintf("prep_datewheel_fun(I('%s'), viz_config, wheel_dates_config, dates_config, datewheel_cfg, callouts_cfg)", format(cur_task$timestep, "%Y-%m-%d %H:%M:%S"))
    }
  )

  gage_sites <- scipiper::create_task_step(
    step_name = 'gage_sites',
    target_name = function(task_name, step_name, ...){
      sprintf('gage_sites_fun_%s', task_name)
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      sprintf("prep_gage_sites_fun(percentile_color_data_ind = '2_process/out/dv_stat_styles.rds.ind',
              sites_sp = site_locations_shifted, dateTime=I('%s'))", format(cur_task$timestep, "%Y-%m-%d %H:%M:%S"))
    },
    depends = "2_process/out/dv_stat_styles.rds"
  )

  callouts <- scipiper::create_task_step(
    step_name = 'callouts',
    target_name = function(task_name, step_name, ...){
      sprintf('callouts_fun_%s', task_name)
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      sprintf("prep_callouts_fun(callouts_cfg = callouts_cfg, dateTime=I('%s'))", format(cur_task$timestep, "%Y-%m-%d %H:%M:%S"))
    }
  )

  # ---- main target for each task: the

  complete_png <- scipiper::create_task_step(
    step_name = 'complete_png',
    target_name = function(task_name, step_name, ...){
      file.path(folders$tmp, sprintf('frame_%s.png', task_name))
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      psprintf(
        "create_animation_frame(",
        "png_file=target_name,",
        "config=timestep_frame_config,",
        "view_fun,",
        "basemap_fun,",
        "title_fun,",
        "footnote_fun,",
        "legend_fun,",
        "watermark_fun,",
        "datewheel_fun_%s,"=cur_task$tn,
        "gage_sites_fun_%s,"=cur_task$tn,
        "callouts_fun_%s)"=cur_task$tn
      )
    }
  )

  # ---- combine into a task plan ---- #

  gif_task_plan <- scipiper::create_task_plan(
    task_names=tasks$task_name,
    task_steps=list(
      datewheel,
      gage_sites,
      callouts,
      complete_png),
    add_complete=FALSE,
    final_steps='complete_png',
    ind_dir=folders$log)
}

create_final_gif_tasks <- function(frame_cfg, folders){

  # prepare a data.frame with one row per task
  # tricking the final frames to be dates starting with 9999-12-31
  total_frames <- frame_cfg$fade_count + frame_cfg$show_count
  timesteps <- as.Date("9999-12-31") - 1*seq_len(total_frames)
  timesteps <- timesteps[order(timesteps)] # reorder chronologically
  tasks <- data_frame(timestep=timesteps) %>%
    mutate(task_name = strftime(timestep, format = '%Y%m%d_%H', tz = 'UTC'),
           fade_count = c(seq(0, 90, length.out=frame_cfg$fade_count),
                          rep("100", frame_cfg$show_count)))

  # ---- main target for each task

  final_png <- scipiper::create_task_step(
    step_name = 'final_png',
    target_name = function(task_name, step_name, ...){
      file.path(folders$tmp, sprintf('frame_%s.png', task_name))
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      psprintf(
        "create_final_frame(",
        "png_file=target_name,",
        "file_config=timestep_frame_config,",
        "frame_config=final_frame_text,",
        sprintf("fade=%s)", cur_task$fade_count)
      )
    }
  )

  # ---- combine into a task plan ---- #

  gif_task_plan <- scipiper::create_task_plan(
    task_names=tasks$task_name,
    task_steps=list(
      final_png),
    add_complete=FALSE,
    final_steps='final_png',
    ind_dir=folders$log)
}

create_pause_gif_tasks <- function(date_cfg, frame_cfg, folders){

  # prepare a data.frame with one row per task
  # tricking the paused frames to be dates starting with 6000-12-31
  timesteps <- as.Date("6000-12-31") - 1*seq_len(frame_cfg$pause_count)
  timesteps <- timesteps[order(timesteps)] # reorder chronologically
  tasks <- data_frame(timestep=timesteps) %>%
    mutate(task_name = strftime(timestep, format = '%Y%m%d_%H', tz = 'UTC'))

  duplicated_frame_timestep <- strftime(date_cfg$end, format = '%Y%m%d_%H', tz = 'UTC')
  duplicated_frame_path <- file.path(folders$tmp, sprintf('frame_%s.png', duplicated_frame_timestep))

  # ---- main target for each task

  pause_png <- scipiper::create_task_step(
    step_name = 'pause_png',
    target_name = function(task_name, step_name, ...){
      file.path(folders$tmp, sprintf('frame_%s.png', task_name))
    },
    command = function(task_name, ...){
      cur_task <- dplyr::filter(rename(tasks, tn=task_name), tn==task_name)
      psprintf(
        "file.copy(",
        sprintf("from='%s',", duplicated_frame_path),
        "to=target_name)"
      )
    }
  )

  # ---- combine into a task plan ---- #

  gif_task_plan <- scipiper::create_task_plan(
    task_names=tasks$task_name,
    task_steps=list(
      pause_png),
    add_complete=FALSE,
    final_steps='pause_png',
    ind_dir=folders$log)
}

# helper function to sprintf a bunch of key-value (string-variableVector) pairs,
# then paste them together with a good separator for constructing remake recipes
psprintf <- function(..., sep='\n      ') {
  args <- list(...)
  non_null_args <- which(!sapply(args, is.null))
  args <- args[non_null_args]
  argnames <- sapply(seq_along(args), function(i) {
    nm <- names(args[i])
    if(!is.null(nm) && nm!='') return(nm)
    val_nm <- names(args[[i]])
    if(!is.null(val_nm) && val_nm!='') return(val_nm)
    return('')
  })
  names(args) <- argnames
  strs <- mapply(function(template, variables) {
    spargs <- if(template == '') list(variables) else c(list(template), as.list(variables))
    do.call(sprintf, spargs)
  }, template=names(args), variables=args)
  paste(strs, collapse=sep)
}
