classdef TextToImageGUI < matlab.apps.AppBase
    
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        MainPanel               matlab.ui.container.Panel
        
        % Left sidebar
        SidebarPanel            matlab.ui.container.Panel
        ImageHistoryLabel       matlab.ui.control.Label
        Image1Button            matlab.ui.control.Button
        Image2Button            matlab.ui.control.Button
        Image3Button            matlab.ui.control.Button
        
        % Parameters panel (left bottom)
        ParametersPanel         matlab.ui.container.Panel
        StepsLabel              matlab.ui.control.Label
        StepsSpinner            matlab.ui.control.Spinner
        GuidanceLabel           matlab.ui.control.Label
        GuidanceSpinner         matlab.ui.control.Spinner
        
        % Main display area
        ImageAxes               matlab.ui.control.UIAxes
        PlaceholderLabel        matlab.ui.control.Label
        
        % Bottom controls
        PromptLabel             matlab.ui.control.Label
        PromptTextArea          matlab.ui.control.TextArea
        GenerateButton          matlab.ui.control.Button
        ClearButton             matlab.ui.control.Button
        
        ProgressLabel           matlab.ui.control.Label
        ProgressGauge           matlab.ui.control.LinearGauge
        SaveButton              matlab.ui.control.Button
        
        GeneratedImage
        ImageHistory = {}
        ModelLoaded = false
    end
    
    methods (Access = private)
        
        function startupFcn(app)
            drawnow;
            
            try
                app.createPythonHelper();
                app.ModelLoaded = true;
                app.updateImageHistoryButtons();
            catch ME
                uialert(app.UIFigure, ME.message, 'Startup Error');
            end
        end
        
        function createPythonHelper(app)
            % Create Python helper file
            fid = fopen('text2img_helper.py', 'w');
            
            fprintf(fid, 'import sys\n');
            fprintf(fid, 'import torch\n');
            fprintf(fid, 'from diffusers import DiffusionPipeline\n');
            fprintf(fid, 'import time\n\n');
            fprintf(fid, 'pipe = None\n\n');
            
            fprintf(fid, 'def progress_callback(pipe, step, timestep, callback_kwargs):\n');
            fprintf(fid, '    total_steps = pipe.num_timesteps\n');
            fprintf(fid, '    progress = int((step / total_steps) * 100)\n');
            fprintf(fid, '    print(f"PROGRESS:{progress}", flush=True)\n');
            fprintf(fid, '    return callback_kwargs\n\n');
            
            fprintf(fid, 'def load_model():\n');
            fprintf(fid, '    global pipe\n');
            fprintf(fid, '    print("PROGRESS:10", flush=True)\n');
            fprintf(fid, '    pipe = DiffusionPipeline.from_pretrained(\n');
            fprintf(fid, '        "UmitDataTeam/fine-diffusion",\n');
            fprintf(fid, '        torch_dtype=torch.float32\n');
            fprintf(fid, '    )\n');
            fprintf(fid, '    print("PROGRESS:20", flush=True)\n');
            fprintf(fid, '    pipe = pipe.to("cpu")\n');
            fprintf(fid, '    pipe.enable_attention_slicing()\n');
            fprintf(fid, '    print("PROGRESS:30", flush=True)\n\n');
            
            fprintf(fid, 'def generate_image(prompt, negative_prompt, steps, guidance, output_file):\n');
            fprintf(fid, '    global pipe\n');
            fprintf(fid, '    if pipe is None:\n');
            fprintf(fid, '        load_model()\n');
            fprintf(fid, '    print("PROGRESS:35", flush=True)\n');
            fprintf(fid, '    result = pipe(\n');
            fprintf(fid, '        prompt=prompt,\n');
            fprintf(fid, '        negative_prompt=negative_prompt,\n');
            fprintf(fid, '        num_inference_steps=int(steps),\n');
            fprintf(fid, '        guidance_scale=float(guidance),\n');
            fprintf(fid, '        height=512,\n');
            fprintf(fid, '        width=512,\n');
            fprintf(fid, '        callback_on_step_end=progress_callback\n');
            fprintf(fid, '    )\n');
            fprintf(fid, '    print("PROGRESS:95", flush=True)\n');
            fprintf(fid, '    image = result.images[0]\n');
            fprintf(fid, '    image.save(output_file)\n');
            fprintf(fid, '    print("PROGRESS:100", flush=True)\n');
            fprintf(fid, '    print("GENERATED", flush=True)\n\n');
            
            fprintf(fid, 'if __name__ == "__main__":\n');
            fprintf(fid, '    if len(sys.argv) < 6:\n');
            fprintf(fid, '        print("Error: Not enough arguments")\n');
            fprintf(fid, '        sys.exit(1)\n');
            fprintf(fid, '    prompt = sys.argv[1]\n');
            fprintf(fid, '    negative_prompt = sys.argv[2]\n');
            fprintf(fid, '    steps = sys.argv[3]\n');
            fprintf(fid, '    guidance = sys.argv[4]\n');
            fprintf(fid, '    output_file = sys.argv[5]\n');
            fprintf(fid, '    generate_image(prompt, negative_prompt, steps, guidance, output_file)\n');
            
            fclose(fid);
        end
        
        function GenerateButtonPushed(app, ~)
            if ~app.ModelLoaded
                uialert(app.UIFigure, 'Model not loaded!', 'Error');
                return;
            end
            
            prompt = app.PromptTextArea.Value{1};
            
            if isempty(prompt)
                uialert(app.UIFigure, 'Please enter a prompt!', 'Warning');
                return;
            end
            
            app.GenerateButton.Enable = 'off';
            app.SaveButton.Enable = 'off';
            app.ClearButton.Enable = 'off';
            
            app.ProgressGauge.Value = 0;
            drawnow;
            
            try
                % Hardcoded negative prompt
                negative_prompt = 'blurry, bad quality, ugly, low resolution, distorted, deformed';
                steps = app.StepsSpinner.Value;
                guidance = app.GuidanceSpinner.Value;
                output_file = 'temp_output.png';
                
                % Delete old file
                if exist(output_file, 'file')
                    delete(output_file);
                end
                
                cmd = sprintf('python text2img_helper.py "%s" "%s" %d %.1f %s', ...
                    prompt, negative_prompt, steps, guidance, output_file);
                
                % Timer for progress bar animation
                progressTimer = timer('ExecutionMode', 'fixedRate', ...
                    'Period', 0.3, ...
                    'TimerFcn', @(~,~) updateProgressBar(app));
                start(progressTimer);
                
                % Run Python script
                [status, result] = system(cmd);
                
                % Stop timer
                stop(progressTimer);
                delete(progressTimer);
                
                % Check result
                if status == 0 && exist(output_file, 'file')
                    app.GeneratedImage = imread(output_file);
                    
                    % Hide placeholder and show image
                    app.PlaceholderLabel.Visible = 'off';
                    imshow(app.GeneratedImage, 'Parent', app.ImageAxes);
                    app.ImageAxes.XTick = [];
                    app.ImageAxes.YTick = [];
                    
                    % Add to history
                    app.addToHistory(output_file);
                    
                    app.ProgressGauge.Value = 100;
                    app.SaveButton.Enable = 'on';
                else
                    error('Could not generate image. Error: %s', result);
                end
                
            catch ME
                app.ProgressGauge.Value = 0;
                uialert(app.UIFigure, ME.message, 'Generation Error');
            end
            
            app.GenerateButton.Enable = 'on';
            app.ClearButton.Enable = 'on';
        end
        
        function addToHistory(app, filepath)
            % Save to history (max 3 images)
            if length(app.ImageHistory) >= 3
                app.ImageHistory(1) = [];
            end
            
            % Copy file with timestamp
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            historyFile = sprintf('image%d.png', length(app.ImageHistory) + 1);
            copyfile(filepath, historyFile);
            
            app.ImageHistory{end+1} = historyFile;
            
            % Update button display
            app.updateImageHistoryButtons();
        end
        
        function updateImageHistoryButtons(app)
            % Scan current directory for PNG images
            pngFiles = dir('*.png');
            pngFiles = {pngFiles.name};
            
            % Filter out temp files
            pngFiles = pngFiles(~contains(pngFiles, 'temp_output'));
            
            % Update buttons with actual filenames
            if length(pngFiles) >= 1
                app.Image1Button.Text = pngFiles{1};
                app.Image1Button.Enable = 'on';
                app.Image1Button.UserData = pngFiles{1};
            else
                app.Image1Button.Text = 'image1.png';
                app.Image1Button.Enable = 'off';
                app.Image1Button.UserData = '';
            end
            
            if length(pngFiles) >= 2
                app.Image2Button.Text = pngFiles{2};
                app.Image2Button.Enable = 'on';
                app.Image2Button.UserData = pngFiles{2};
            else
                app.Image2Button.Text = 'image2.png';
                app.Image2Button.Enable = 'off';
                app.Image2Button.UserData = '';
            end
            
            if length(pngFiles) >= 3
                app.Image3Button.Text = pngFiles{3};
                app.Image3Button.Enable = 'on';
                app.Image3Button.UserData = pngFiles{3};
            else
                app.Image3Button.Text = 'image3.png';
                app.Image3Button.Enable = 'off';
                app.Image3Button.UserData = '';
            end
        end
        
        function loadHistoryImage(app, button)
            filename = button.UserData;
            if ~isempty(filename) && exist(filename, 'file')
                img = imread(filename);
                app.GeneratedImage = img;
                app.PlaceholderLabel.Visible = 'off';
                imshow(img, 'Parent', app.ImageAxes);
                app.ImageAxes.XTick = [];
                app.ImageAxes.YTick = [];
                app.SaveButton.Enable = 'on';
            end
        end
        
        function updateProgressBar(app)
            % Update progress bar with animation
            currentValue = app.ProgressGauge.Value;
            
            if currentValue < 20
                app.ProgressGauge.Value = currentValue + 5;
            elseif currentValue < 85
                app.ProgressGauge.Value = currentValue + 2;
            elseif currentValue < 95
                app.ProgressGauge.Value = currentValue + 1;
            end
            
            drawnow;
        end
        
        function SaveButtonPushed(app, ~)
            if isempty(app.GeneratedImage)
                uialert(app.UIFigure, 'No image to save!', 'Warning');
                return;
            end
            
            [file, path] = uiputfile({'*.png';'*.jpg';'*.jpeg'}, 'Save Image');
            
            if file ~= 0
                filepath = fullfile(path, file);
                imwrite(app.GeneratedImage, filepath);
            end
        end
        
        function ClearButtonPushed(app, ~)
            cla(app.ImageAxes);
            app.PlaceholderLabel.Visible = 'on';
            app.GeneratedImage = [];
            app.ProgressGauge.Value = 0;
            app.SaveButton.Enable = 'off';
        end
    end
    
    methods (Access = private)
        
        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 900 600];
            app.UIFigure.Name = 'Text-to-Image Generator';
            app.UIFigure.Resize = 'off';
            app.UIFigure.Color = [1 1 1];
            
            % Left sidebar panel
            app.SidebarPanel = uipanel(app.UIFigure);
            app.SidebarPanel.Position = [10 10 170 580];
            app.SidebarPanel.BackgroundColor = [0.75 0.75 0.75];
            app.SidebarPanel.BorderType = 'none';
            
            app.ImageHistoryLabel = uilabel(app.SidebarPanel);
            app.ImageHistoryLabel.Position = [10 540 150 30];
            app.ImageHistoryLabel.Text = 'Other Images in Same Directory';
            app.ImageHistoryLabel.FontSize = 11;
            app.ImageHistoryLabel.FontWeight = 'bold';
            app.ImageHistoryLabel.WordWrap = 'on';
            app.ImageHistoryLabel.HorizontalAlignment = 'center';
            
            % History image buttons
            app.Image1Button = uibutton(app.SidebarPanel, 'push');
            app.Image1Button.Position = [10 480 150 40];
            app.Image1Button.Text = 'image1.png';
            app.Image1Button.Enable = 'off';
            app.Image1Button.ButtonPushedFcn = @(btn,~) loadHistoryImage(app, btn);
            
            app.Image2Button = uibutton(app.SidebarPanel, 'push');
            app.Image2Button.Position = [10 430 150 40];
            app.Image2Button.Text = 'image2.png';
            app.Image2Button.Enable = 'off';
            app.Image2Button.ButtonPushedFcn = @(btn,~) loadHistoryImage(app, btn);
            
            app.Image3Button = uibutton(app.SidebarPanel, 'push');
            app.Image3Button.Position = [10 380 150 40];
            app.Image3Button.Text = 'image3.png';
            app.Image3Button.Enable = 'off';
            app.Image3Button.ButtonPushedFcn = @(btn,~) loadHistoryImage(app, btn);
            
            % Parameters panel - below sidebar
            app.ParametersPanel = uipanel(app.UIFigure);
            app.ParametersPanel.Title = 'Parameters';
            app.ParametersPanel.Position = [10 160 170 120];
            app.ParametersPanel.FontWeight = 'bold';
            app.ParametersPanel.BackgroundColor = [0.9 0.9 0.9];
            
            app.StepsLabel = uilabel(app.ParametersPanel);
            app.StepsLabel.Position = [10 60 60 22];
            app.StepsLabel.Text = 'Steps:';
            
            app.StepsSpinner = uispinner(app.ParametersPanel);
            app.StepsSpinner.Position = [75 60 80 22];
            app.StepsSpinner.Value = 25;
            app.StepsSpinner.Limits = [10 50];
            app.StepsSpinner.Step = 5;
            
            app.GuidanceLabel = uilabel(app.ParametersPanel);
            app.GuidanceLabel.Position = [10 25 60 22];
            app.GuidanceLabel.Text = 'Guidance:';
            
            app.GuidanceSpinner = uispinner(app.ParametersPanel);
            app.GuidanceSpinner.Position = [75 25 80 22];
            app.GuidanceSpinner.Value = 7.5;
            app.GuidanceSpinner.Limits = [1 20];
            app.GuidanceSpinner.Step = 0.5;
            
            % Main display area
            app.ImageAxes = uiaxes(app.UIFigure);
            app.ImageAxes.Position = [200 160 680 430];
            app.ImageAxes.XTick = [];
            app.ImageAxes.YTick = [];
            app.ImageAxes.Box = 'on';
            app.ImageAxes.XColor = [0.5 0.5 0.5];
            app.ImageAxes.YColor = [0.5 0.5 0.5];
            app.ImageAxes.Color = [0.8 0.8 0.8];
            
            % Placeholder text
            app.PlaceholderLabel = uilabel(app.UIFigure);
            app.PlaceholderLabel.Position = [200 160 680 430];
            app.PlaceholderLabel.Text = {'Image'; 'Will Appear'; 'Here'};
            app.PlaceholderLabel.FontSize = 36;
            app.PlaceholderLabel.FontWeight = 'bold';
            app.PlaceholderLabel.FontColor = [0.3 0.3 0.3];
            app.PlaceholderLabel.HorizontalAlignment = 'center';
            app.PlaceholderLabel.VerticalAlignment = 'center';
            
            % Prompt label and text area
            app.PromptLabel = uilabel(app.UIFigure);
            app.PromptLabel.Position = [200 130 80 22];
            app.PromptLabel.Text = 'Prompt';
            app.PromptLabel.FontWeight = 'bold';
            
            app.PromptTextArea = uitextarea(app.UIFigure);
            app.PromptTextArea.Position = [200 80 440 45];
            app.PromptTextArea.Value = {''};
            
            % Generate and Clear buttons
            app.GenerateButton = uibutton(app.UIFigure, 'push');
            app.GenerateButton.Position = [650 80 100 45];
            app.GenerateButton.Text = 'Generate';
            app.GenerateButton.FontSize = 12;
            app.GenerateButton.FontWeight = 'bold';
            app.GenerateButton.ButtonPushedFcn = createCallbackFcn(app, @GenerateButtonPushed, true);
            
            app.ClearButton = uibutton(app.UIFigure, 'push');
            app.ClearButton.Position = [760 80 120 45];
            app.ClearButton.Text = 'Clear';
            app.ClearButton.FontSize = 12;
            app.ClearButton.ButtonPushedFcn = createCallbackFcn(app, @ClearButtonPushed, true);
            
            % Progress bar label and gauge
            app.ProgressLabel = uilabel(app.UIFigure);
            app.ProgressLabel.Position = [200 50 100 22];
            app.ProgressLabel.Text = 'Progress Bar';
            app.ProgressLabel.FontWeight = 'bold';
            
            app.ProgressGauge = uigauge(app.UIFigure, 'linear');
            app.ProgressGauge.Position = [200 15 440 35];
            app.ProgressGauge.Limits = [0 100];
            app.ProgressGauge.Value = 0;
            
            % Save button
            app.SaveButton = uibutton(app.UIFigure, 'push');
            app.SaveButton.Position = [650 20 230 45];
            app.SaveButton.Text = 'Save';
            app.SaveButton.FontSize = 12;
            app.SaveButton.FontWeight = 'bold';
            app.SaveButton.Enable = 'off';
            app.SaveButton.ButtonPushedFcn = createCallbackFcn(app, @SaveButtonPushed, true);
            
            app.UIFigure.Visible = 'on';
        end
    end
    
    methods (Access = public)
        
        function app = TextToImageGUI
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            
            if nargout == 0
                clear app
            end
        end
        
        function delete(app)
            delete(app.UIFigure)
        end
    end
end