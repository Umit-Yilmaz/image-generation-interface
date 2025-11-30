classdef ImageProcessingApp < matlab.apps.AppBase
    
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        TabGroup               matlab.ui.container.TabGroup
        
        % Tab 1: Style Transfer
        StyleTransferTab       matlab.ui.container.Tab
        ST_SidebarPanel        matlab.ui.container.Panel
        ST_ImageButtons        cell
        ST_TargetImageAxes     matlab.ui.control.UIAxes
        ST_ContentImageAxes    matlab.ui.control.UIAxes
        ST_OutputAxes          matlab.ui.control.UIAxes
        ST_ChooseTargetBtn     matlab.ui.control.Button
        ST_ChooseContentBtn    matlab.ui.control.Button
        ST_SaveOutputBtn       matlab.ui.control.Button
        ST_ClearAllBtn         matlab.ui.control.Button
        ST_TargetImage
        ST_ContentImage
        ST_OutputImage
        ST_SelectedModel
        ST_SelectedModelName
        
        % Tab 2: Real-Time Style Transfer
        RTTab                  matlab.ui.container.Tab
        RT_SidebarPanel        matlab.ui.container.Panel
        RT_ImageButtons        cell
        RT_TargetImageAxes     matlab.ui.control.UIAxes
        RT_VideoAxes           matlab.ui.control.UIAxes
        RT_OutputAxes          matlab.ui.control.UIAxes
        RT_ChooseTargetBtn     matlab.ui.control.Button
        RT_StartStopBtn        matlab.ui.control.Button
        RT_Camera
        RT_IsRunning = false
        RT_SelectedModel
        RT_SelectedModelName
        
        % Tab 3: Image Generator
        IGTab                  matlab.ui.container.Tab
        IG_SidebarPanel        matlab.ui.container.Panel
        IG_ImageButtons        cell
        IG_ImageAxes           matlab.ui.control.UIAxes
        IG_PlaceholderLabel    matlab.ui.control.Label
        IG_PromptLabel         matlab.ui.control.Label
        IG_PromptTextArea      matlab.ui.control.TextArea
        IG_GenerateButton      matlab.ui.control.Button
        IG_ClearButton         matlab.ui.control.Button
        IG_SaveButton          matlab.ui.control.Button
        IG_ProgressLabel       matlab.ui.control.Label
        IG_ProgressGauge       matlab.ui.control.LinearGauge
        IG_ParametersPanel     matlab.ui.container.Panel
        IG_StepsLabel          matlab.ui.control.Label
        IG_StepsSpinner        matlab.ui.control.Spinner
        IG_GuidanceLabel       matlab.ui.control.Label
        IG_GuidanceSpinner     matlab.ui.control.Spinner
        IG_GeneratedImage
        IG_ModelLoaded = false
    end
    
    methods (Access = private)
        
        function startupFcn(app)
            drawnow;
            
            % Initialize Style Transfer tab
            app.updateSidebarImages('StyleTransfer');
            
            % Initialize Real-Time Style Transfer tab
            app.updateSidebarImages('RealTime');
            
            % Initialize Image Generator tab
            app.updateSidebarImages('ImageGenerator');
            
            try
                app.createPythonHelper();
                app.IG_ModelLoaded = true;
            catch ME
                warning(['Image Generator initialization failed: ' ME.message]);
            end
        end
        
        %% Style Transfer Functions
        
        function ST_ChooseTargetImage(app)
            % Choose target image from styles folder
            stylesPath = fullfile(pwd, 'stlyes');
            if ~exist(stylesPath, 'dir')
                stylesPath = pwd;
            end
            
            [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp'}, ...
                'Select Target Style Image', stylesPath);
            
            if isequal(file, 0)
                return;
            end
            
            % Load target image
            fullPath = fullfile(path, file);
            app.ST_TargetImage = imread(fullPath);
            
            % Display target image
            cla(app.ST_TargetImageAxes);
            imshow(app.ST_TargetImage, 'Parent', app.ST_TargetImageAxes);
            title(app.ST_TargetImageAxes, 'Choose Target Image', 'FontSize', 12);
            
            % Find corresponding .mat file
            [~, baseName, ~] = fileparts(file);
            matFile = fullfile(path, [baseName '.mat']);
            
            if exist(matFile, 'file')
                try
                    modelData = load(matFile);
                    fieldNames = fieldnames(modelData);
                    app.ST_SelectedModel = modelData.(fieldNames{1});
                    app.ST_SelectedModelName = baseName;
                catch ME
                    uialert(app.UIFigure, ['Failed to load model: ' ME.message], 'Error');
                end
            else
                uialert(app.UIFigure, ['Model file not found: ' matFile], 'Warning');
            end
        end
        
        function ST_ChooseContentImage(app)
            [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp'}, ...
                'Select Content Image');
            
            if isequal(file, 0)
                return;
            end
            
            % Load content image
            fullPath = fullfile(path, file);
            app.ST_ContentImage = imread(fullPath);
            
            % Display content image
            cla(app.ST_ContentImageAxes);
            imshow(app.ST_ContentImage, 'Parent', app.ST_ContentImageAxes);
            title(app.ST_ContentImageAxes, 'Choose Content Image', 'FontSize', 12);
            
            % Apply style transfer if both images are loaded
            if ~isempty(app.ST_TargetImage) && ~isempty(app.ST_ContentImage) && ~isempty(app.ST_SelectedModel)
                app.applyStyleTransfer();
            end
        end
        
        function applyStyleTransfer(app)
            if isempty(app.ST_ContentImage)
                uialert(app.UIFigure, 'Please select a content image first.', 'No Image');
                return;
            end
            
            if isempty(app.ST_SelectedModel)
                uialert(app.UIFigure, 'Please select a target style image with a model.', 'No Model');
                return;
            end
            
            pd = uiprogressdlg(app.UIFigure, ...
                'Title', 'Applying Style Transfer', ...
                'Message', 'Processing...', ...
                'Indeterminate', 'on');
            
            try
                img = app.ST_ContentImage;
                
                % Convert grayscale to RGB if needed
                if size(img, 3) == 1
                    img = repmat(img, 1, 1, 3);
                end
                
                % Resize and prepare image
                imgResized = imresize(img, [256 256]);
                imgSingle = single(imgResized);
                
                % Create dlarray with SSCB format
                dlImg = dlarray(imgSingle, 'SSCB');
                
                % Use GPU if available
                if canUseGPU()
                    dlImg = gpuArray(dlImg);
                end
                
                pd.Indeterminate = 'off';
                pd.Value = 0.5;
                pd.Message = 'Running neural network...';
                drawnow;
                
                % Apply style transfer
                stylized = predict(app.ST_SelectedModel, dlImg);
                
                % Post-process output
                stylized = 255 * (tanh(stylized) + 1) / 2;
                stylized = uint8(gather(extractdata(stylized)));
                
                app.ST_OutputImage = stylized;
                
                % Display output
                cla(app.ST_OutputAxes);
                imshow(stylized, 'Parent', app.ST_OutputAxes);
                title(app.ST_OutputAxes, 'Output', 'FontSize', 12);
                
                app.ST_SaveOutputBtn.Enable = 'on';
                
                pd.Value = 1;
                pd.Message = 'Done!';
                pause(0.3);
                close(pd);
                
            catch ME
                close(pd);
                uialert(app.UIFigure, ['Error: ' ME.message], 'Style Transfer Failed');
            end
        end
        
        function ST_SaveOutput(app)
            if isempty(app.ST_OutputImage)
                uialert(app.UIFigure, 'No output image to save!', 'Warning');
                return;
            end
            
            [file, path] = uiputfile({'*.png';'*.jpg';'*.jpeg'}, 'Save Output Image');
            
            if file ~= 0
                filepath = fullfile(path, file);
                imwrite(app.ST_OutputImage, filepath);
                uialert(app.UIFigure, 'Image saved successfully!', 'Success');
            end
        end
        
        function ST_ClearAll(app)
            cla(app.ST_TargetImageAxes);
            cla(app.ST_ContentImageAxes);
            cla(app.ST_OutputAxes);
            
            title(app.ST_TargetImageAxes, 'Choose Target Image', 'FontSize', 12);
            title(app.ST_ContentImageAxes, 'Choose Content Image', 'FontSize', 12);
            title(app.ST_OutputAxes, 'Output', 'FontSize', 12);
            
            app.ST_TargetImage = [];
            app.ST_ContentImage = [];
            app.ST_OutputImage = [];
            app.ST_SelectedModel = [];
            app.ST_SaveOutputBtn.Enable = 'off';
        end
        
        %% Real-Time Style Transfer Functions
        
        function RT_ChooseTargetImage(app)
            % Choose target image from styles folder
            stylesPath = fullfile(pwd, 'stlyes');
            if ~exist(stylesPath, 'dir')
                stylesPath = pwd;
            end
            
            [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp'}, ...
                'Select Target Style Image', stylesPath);
            
            if isequal(file, 0)
                return;
            end
            
            % Load and display target image
            fullPath = fullfile(path, file);
            targetImage = imread(fullPath);
            
            cla(app.RT_TargetImageAxes);
            imshow(targetImage, 'Parent', app.RT_TargetImageAxes);
            title(app.RT_TargetImageAxes, 'Choose Target Image', 'FontSize', 12);
            
            % Find corresponding .mat file
            [~, baseName, ~] = fileparts(file);
            matFile = fullfile(path, [baseName '.mat']);
            
            if exist(matFile, 'file')
                try
                    modelData = load(matFile);
                    fieldNames = fieldnames(modelData);
                    app.RT_SelectedModel = modelData.(fieldNames{1});
                    app.RT_SelectedModelName = baseName;
                catch ME
                    uialert(app.UIFigure, ['Failed to load model: ' ME.message], 'Error');
                end
            else
                uialert(app.UIFigure, ['Model file not found: ' matFile], 'Warning');
            end
        end
        
        function RT_StartStop(app)
            if ~app.RT_IsRunning
                % Start real-time processing
                if isempty(app.RT_SelectedModel)
                    uialert(app.UIFigure, 'Please select a target style image first.', 'No Model');
                    return;
                end
                
                try
                    % Initialize webcam
                    app.RT_Camera = webcam;
                    app.RT_IsRunning = true;
                    app.RT_StartStopBtn.Text = 'Stop';
                    app.RT_StartStopBtn.BackgroundColor = [0.85 0.33 0.10];
                    
                    % Start video loop
                    while app.RT_IsRunning && isvalid(app.UIFigure)
                        % Capture frame
                        frame = snapshot(app.RT_Camera);
                        
                        % Display input frame
                        cla(app.RT_VideoAxes);
                        imshow(frame, 'Parent', app.RT_VideoAxes);
                        title(app.RT_VideoAxes, 'Web Cam Real Time Video Input', 'FontSize', 12);
                        
                        % Apply style transfer
                        try
                            imgResized = imresize(frame, [256 256]);
                            imgSingle = single(imgResized);
                            dlImg = dlarray(imgSingle, 'SSCB');
                            
                            if canUseGPU()
                                dlImg = gpuArray(dlImg);
                            end
                            
                            stylized = predict(app.RT_SelectedModel, dlImg);
                            stylized = 255 * (tanh(stylized) + 1) / 2;
                            stylized = uint8(gather(extractdata(stylized)));
                            
                            % Display styled frame
                            cla(app.RT_OutputAxes);
                            imshow(stylized, 'Parent', app.RT_OutputAxes);
                            title(app.RT_OutputAxes, 'Real Time Styled Video Output', 'FontSize', 12);
                        catch
                            % Continue even if style transfer fails
                        end
                        
                        drawnow;
                    end
                    
                catch ME
                    uialert(app.UIFigure, ['Camera error: ' ME.message], 'Error');
                end
            else
                % Stop real-time processing
                app.RT_IsRunning = false;
                app.RT_StartStopBtn.Text = 'Start';
                app.RT_StartStopBtn.BackgroundColor = [0.65 0.65 0.65];
                
                if ~isempty(app.RT_Camera)
                    clear app.RT_Camera;
                end
            end
        end
        
        %% Image Generator Functions
        
        function createPythonHelper(app)
            % Create Python helper file for text-to-image generation
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
        
        function IG_Generate(app)
            if ~app.IG_ModelLoaded
                uialert(app.UIFigure, 'Model not loaded!', 'Error');
                return;
            end
            
            if isempty(app.IG_PromptTextArea.Value) || isempty(app.IG_PromptTextArea.Value{1})
                uialert(app.UIFigure, 'Please enter a prompt!', 'Warning');
                return;
            end
            
            prompt = app.IG_PromptTextArea.Value{1};
            
            app.IG_GenerateButton.Enable = 'off';
            app.IG_SaveButton.Enable = 'off';
            app.IG_ClearButton.Enable = 'off';
            
            app.IG_ProgressGauge.Value = 0;
            drawnow;
            
            try
                negative_prompt = 'blurry, bad quality, ugly, low resolution, distorted, deformed';
                steps = app.IG_StepsSpinner.Value;
                guidance = app.IG_GuidanceSpinner.Value;
                output_file = 'temp_output.png';
                
                if exist(output_file, 'file')
                    delete(output_file);
                end
                
                cmd = sprintf('python text2img_helper.py "%s" "%s" %d %.1f %s', ...
                    prompt, negative_prompt, steps, guidance, output_file);
                
                % Progress animation timer
                progressTimer = timer('ExecutionMode', 'fixedRate', ...
                    'Period', 0.3, ...
                    'TimerFcn', @(~,~) IG_updateProgressBar(app));
                start(progressTimer);
                
                % Run Python script
                [status, result] = system(cmd);
                
                stop(progressTimer);
                delete(progressTimer);
                
                if status == 0 && exist(output_file, 'file')
                    app.IG_GeneratedImage = imread(output_file);
                    
                    app.IG_PlaceholderLabel.Visible = 'off';
                    cla(app.IG_ImageAxes);
                    imshow(app.IG_GeneratedImage, 'Parent', app.IG_ImageAxes);
                    
                    % Save to history
                    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
                    historyFile = sprintf('generated_%s.png', timestamp);
                    copyfile(output_file, historyFile);
                    
                    app.updateSidebarImages('ImageGenerator');
                    
                    app.IG_ProgressGauge.Value = 100;
                    app.IG_SaveButton.Enable = 'on';
                else
                    error('Could not generate image. Error: %s', result);
                end
                
            catch ME
                app.IG_ProgressGauge.Value = 0;
                uialert(app.UIFigure, ME.message, 'Generation Error');
            end
            
            app.IG_GenerateButton.Enable = 'on';
            app.IG_ClearButton.Enable = 'on';
        end
        
        function IG_updateProgressBar(app)
            currentValue = app.IG_ProgressGauge.Value;
            
            if currentValue < 20
                app.IG_ProgressGauge.Value = currentValue + 5;
            elseif currentValue < 85
                app.IG_ProgressGauge.Value = currentValue + 2;
            elseif currentValue < 95
                app.IG_ProgressGauge.Value = currentValue + 1;
            end
            
            drawnow;
        end
        
        function IG_Clear(app)
            cla(app.IG_ImageAxes);
            app.IG_PlaceholderLabel.Visible = 'on';
            app.IG_GeneratedImage = [];
            app.IG_ProgressGauge.Value = 0;
            app.IG_SaveButton.Enable = 'off';
        end
        
        function IG_Save(app)
            if isempty(app.IG_GeneratedImage)
                uialert(app.UIFigure, 'No image to save!', 'Warning');
                return;
            end
            
            [file, path] = uiputfile({'*.png';'*.jpg';'*.jpeg'}, 'Save Image');
            
            if file ~= 0
                filepath = fullfile(path, file);
                imwrite(app.IG_GeneratedImage, filepath);
                uialert(app.UIFigure, 'Image saved successfully!', 'Success');
            end
        end
        
        %% Sidebar Functions
        
        function updateSidebarImages(app, tabName)
            % Get all image files in current directory
            imageFiles = dir('*.png');
            imageFiles = [imageFiles; dir('*.jpg')];
            imageFiles = [imageFiles; dir('*.jpeg')];
            
            % Filter out temp files
            imageFiles = imageFiles(~contains({imageFiles.name}, 'temp_'));
            
            % Limit to 6 most recent files
            if length(imageFiles) > 6
                [~, idx] = sort([imageFiles.datenum], 'descend');
                imageFiles = imageFiles(idx(1:6));
            end
            
            switch tabName
                case 'StyleTransfer'
                    buttons = app.ST_ImageButtons;
                case 'RealTime'
                    buttons = app.RT_ImageButtons;
                case 'ImageGenerator'
                    buttons = app.IG_ImageButtons;
            end
            
            % Update buttons
            for i = 1:6
                if i <= length(imageFiles)
                    buttons{i}.Text = imageFiles(i).name;
                    buttons{i}.Enable = 'on';
                    buttons{i}.UserData = imageFiles(i).name;
                else
                    buttons{i}.Text = sprintf('Image %d', i);
                    buttons{i}.Enable = 'off';
                    buttons{i}.UserData = '';
                end
            end
        end
        
        function loadSidebarImage(app, button, tabName)
            filename = button.UserData;
            if isempty(filename) || ~exist(filename, 'file')
                return;
            end
            
            img = imread(filename);
            
            switch tabName
                case 'StyleTransfer'
                    app.ST_ContentImage = img;
                    cla(app.ST_ContentImageAxes);
                    imshow(img, 'Parent', app.ST_ContentImageAxes);
                    title(app.ST_ContentImageAxes, 'Choose Content Image', 'FontSize', 12);
                    
                    if ~isempty(app.ST_TargetImage) && ~isempty(app.ST_SelectedModel)
                        app.applyStyleTransfer();
                    end
                    
                case 'ImageGenerator'
                    app.IG_GeneratedImage = img;
                    app.IG_PlaceholderLabel.Visible = 'off';
                    cla(app.IG_ImageAxes);
                    imshow(img, 'Parent', app.IG_ImageAxes);
                    app.IG_SaveButton.Enable = 'on';
            end
        end
        
    end
    
    methods (Access = private)
        
        function createComponents(app)
            % Create UIFigure
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1000 650];
            app.UIFigure.Name = 'Image Processing Application';
            app.UIFigure.Resize = 'on';
            app.UIFigure.Color = [0.94 0.94 0.94];
            
            % Create TabGroup
            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [10 10 980 630];
            
            %% Create Style Transfer Tab
            app.StyleTransferTab = uitab(app.TabGroup);
            app.StyleTransferTab.Title = 'Style Transfer';
            app.StyleTransferTab.BackgroundColor = [1 1 1];
            
            % Title
            titleLabel = uilabel(app.StyleTransferTab);
            titleLabel.Text = 'Style Transfer';
            titleLabel.Position = [190 540 600 40];
            titleLabel.FontSize = 24;
            titleLabel.FontWeight = 'bold';
            titleLabel.HorizontalAlignment = 'center';
            
            % Sidebar
            app.ST_SidebarPanel = uipanel(app.StyleTransferTab);
            app.ST_SidebarPanel.Position = [10 10 150 570];
            app.ST_SidebarPanel.BackgroundColor = [0.75 0.75 0.75];
            app.ST_SidebarPanel.BorderType = 'none';
            
            sidebarLabel = uilabel(app.ST_SidebarPanel);
            sidebarLabel.Position = [5 540 140 25];
            sidebarLabel.Text = 'Images From Directory';
            sidebarLabel.FontSize = 9;
            sidebarLabel.FontWeight = 'bold';
            sidebarLabel.HorizontalAlignment = 'center';
            sidebarLabel.WordWrap = 'on';
            
            % Create 6 image buttons
            app.ST_ImageButtons = cell(6, 1);
            for i = 1:6
                app.ST_ImageButtons{i} = uibutton(app.ST_SidebarPanel, 'push');
                app.ST_ImageButtons{i}.Position = [10 480-(i-1)*60 130 45];
                app.ST_ImageButtons{i}.Text = sprintf('Image %d', i);
                app.ST_ImageButtons{i}.Enable = 'off';
                app.ST_ImageButtons{i}.BackgroundColor = [0.65 0.65 0.65];
                app.ST_ImageButtons{i}.FontSize = 9;
                app.ST_ImageButtons{i}.ButtonPushedFcn = @(btn,~) loadSidebarImage(app, btn, 'StyleTransfer');
            end
            
            % Image axes
            app.ST_TargetImageAxes = uiaxes(app.StyleTransferTab);
            app.ST_TargetImageAxes.Position = [180 230 220 290];
            app.ST_TargetImageAxes.XTick = [];
            app.ST_TargetImageAxes.YTick = [];
            app.ST_TargetImageAxes.Box = 'on';
            app.ST_TargetImageAxes.Color = [0.75 0.75 0.75];
            title(app.ST_TargetImageAxes, 'Target Image', 'FontSize', 11);
            
            app.ST_ContentImageAxes = uiaxes(app.StyleTransferTab);
            app.ST_ContentImageAxes.Position = [420 230 220 290];
            app.ST_ContentImageAxes.XTick = [];
            app.ST_ContentImageAxes.YTick = [];
            app.ST_ContentImageAxes.Box = 'on';
            app.ST_ContentImageAxes.Color = [0.75 0.75 0.75];
            title(app.ST_ContentImageAxes, 'Content Image', 'FontSize', 11);
            
            app.ST_OutputAxes = uiaxes(app.StyleTransferTab);
            app.ST_OutputAxes.Position = [660 230 220 290];
            app.ST_OutputAxes.XTick = [];
            app.ST_OutputAxes.YTick = [];
            app.ST_OutputAxes.Box = 'on';
            app.ST_OutputAxes.Color = [0.75 0.75 0.75];
            title(app.ST_OutputAxes, 'Output', 'FontSize', 11);
            
            % Buttons
            app.ST_ChooseTargetBtn = uibutton(app.StyleTransferTab, 'push');
            app.ST_ChooseTargetBtn.Position = [195 160 190 45];
            app.ST_ChooseTargetBtn.Text = 'Choose Target';
            app.ST_ChooseTargetBtn.FontSize = 11;
            app.ST_ChooseTargetBtn.BackgroundColor = [0.65 0.65 0.65];
            app.ST_ChooseTargetBtn.ButtonPushedFcn = @(~,~) app.ST_ChooseTargetImage();
            
            app.ST_ChooseContentBtn = uibutton(app.StyleTransferTab, 'push');
            app.ST_ChooseContentBtn.Position = [435 160 190 45];
            app.ST_ChooseContentBtn.Text = 'Choose Content';
            app.ST_ChooseContentBtn.FontSize = 11;
            app.ST_ChooseContentBtn.BackgroundColor = [0.65 0.65 0.65];
            app.ST_ChooseContentBtn.ButtonPushedFcn = @(~,~) app.ST_ChooseContentImage();
            
            app.ST_SaveOutputBtn = uibutton(app.StyleTransferTab, 'push');
            app.ST_SaveOutputBtn.Position = [675 160 190 45];
            app.ST_SaveOutputBtn.Text = 'Save Output';
            app.ST_SaveOutputBtn.FontSize = 11;
            app.ST_SaveOutputBtn.BackgroundColor = [0.65 0.65 0.65];
            app.ST_SaveOutputBtn.Enable = 'off';
            app.ST_SaveOutputBtn.ButtonPushedFcn = @(~,~) app.ST_SaveOutput();
            
            app.ST_ClearAllBtn = uibutton(app.StyleTransferTab, 'push');
            app.ST_ClearAllBtn.Position = [400 80 200 45];
            app.ST_ClearAllBtn.Text = 'Clear All';
            app.ST_ClearAllBtn.FontSize = 11;
            app.ST_ClearAllBtn.BackgroundColor = [0.65 0.65 0.65];
            app.ST_ClearAllBtn.ButtonPushedFcn = @(~,~) app.ST_ClearAll();
            
            %% Create Real-Time Style Transfer Tab
            app.RTTab = uitab(app.TabGroup);
            app.RTTab.Title = 'Real Time Style Transfer';
            app.RTTab.BackgroundColor = [1 1 1];
            
            % Title
            rtTitleLabel = uilabel(app.RTTab);
            rtTitleLabel.Text = 'Real Time Style Transfer';
            rtTitleLabel.Position = [190 540 600 40];
            rtTitleLabel.FontSize = 24;
            rtTitleLabel.FontWeight = 'bold';
            rtTitleLabel.HorizontalAlignment = 'center';
            
            % Sidebar
            app.RT_SidebarPanel = uipanel(app.RTTab);
            app.RT_SidebarPanel.Position = [10 10 150 570];
            app.RT_SidebarPanel.BackgroundColor = [0.75 0.75 0.75];
            app.RT_SidebarPanel.BorderType = 'none';
            
            rtSidebarLabel = uilabel(app.RT_SidebarPanel);
            rtSidebarLabel.Position = [5 540 140 25];
            rtSidebarLabel.Text = 'Images From Directory';
            rtSidebarLabel.FontSize = 9;
            rtSidebarLabel.FontWeight = 'bold';
            rtSidebarLabel.HorizontalAlignment = 'center';
            rtSidebarLabel.WordWrap = 'on';
            
            % Create 6 image buttons
            app.RT_ImageButtons = cell(6, 1);
            for i = 1:6
                app.RT_ImageButtons{i} = uibutton(app.RT_SidebarPanel, 'push');
                app.RT_ImageButtons{i}.Position = [10 480-(i-1)*60 130 45];
                app.RT_ImageButtons{i}.Text = sprintf('Image %d', i);
                app.RT_ImageButtons{i}.Enable = 'off';
                app.RT_ImageButtons{i}.BackgroundColor = [0.65 0.65 0.65];
                app.RT_ImageButtons{i}.FontSize = 9;
            end
            
            % Image axes
            app.RT_TargetImageAxes = uiaxes(app.RTTab);
            app.RT_TargetImageAxes.Position = [180 230 200 290];
            app.RT_TargetImageAxes.XTick = [];
            app.RT_TargetImageAxes.YTick = [];
            app.RT_TargetImageAxes.Box = 'on';
            app.RT_TargetImageAxes.Color = [0.75 0.75 0.75];
            title(app.RT_TargetImageAxes, 'Target Image', 'FontSize', 11);
            
            app.RT_VideoAxes = uiaxes(app.RTTab);
            app.RT_VideoAxes.Position = [400 230 240 290];
            app.RT_VideoAxes.XTick = [];
            app.RT_VideoAxes.YTick = [];
            app.RT_VideoAxes.Box = 'on';
            app.RT_VideoAxes.Color = [0.75 0.75 0.75];
            title(app.RT_VideoAxes, 'Webcam Input', 'FontSize', 11);
            
            app.RT_OutputAxes = uiaxes(app.RTTab);
            app.RT_OutputAxes.Position = [660 230 240 290];
            app.RT_OutputAxes.XTick = [];
            app.RT_OutputAxes.YTick = [];
            app.RT_OutputAxes.Box = 'on';
            app.RT_OutputAxes.Color = [0.75 0.75 0.75];
            title(app.RT_OutputAxes, 'Styled Output', 'FontSize', 11);
            
            % Buttons
            app.RT_ChooseTargetBtn = uibutton(app.RTTab, 'push');
            app.RT_ChooseTargetBtn.Position = [210 140 150 45];
            app.RT_ChooseTargetBtn.Text = 'Choose Target';
            app.RT_ChooseTargetBtn.FontSize = 11;
            app.RT_ChooseTargetBtn.BackgroundColor = [0.65 0.65 0.65];
            app.RT_ChooseTargetBtn.ButtonPushedFcn = @(~,~) app.RT_ChooseTargetImage();
            
            app.RT_StartStopBtn = uibutton(app.RTTab, 'push');
            app.RT_StartStopBtn.Position = [450 70 160 50];
            app.RT_StartStopBtn.Text = 'Start';
            app.RT_StartStopBtn.FontSize = 13;
            app.RT_StartStopBtn.FontWeight = 'bold';
            app.RT_StartStopBtn.BackgroundColor = [0.65 0.65 0.65];
            app.RT_StartStopBtn.ButtonPushedFcn = @(~,~) app.RT_StartStop();
            
            %% Create Image Generator Tab
            app.IGTab = uitab(app.TabGroup);
            app.IGTab.Title = 'Image Generator';
            app.IGTab.BackgroundColor = [1 1 1];
            
            % Title
            igTitleLabel = uilabel(app.IGTab);
            igTitleLabel.Text = 'Image Generator';
            igTitleLabel.Position = [190 540 600 40];
            igTitleLabel.FontSize = 24;
            igTitleLabel.FontWeight = 'bold';
            igTitleLabel.HorizontalAlignment = 'center';
            
            % Sidebar
            app.IG_SidebarPanel = uipanel(app.IGTab);
            app.IG_SidebarPanel.Position = [10 10 150 570];
            app.IG_SidebarPanel.BackgroundColor = [0.75 0.75 0.75];
            app.IG_SidebarPanel.BorderType = 'none';
            
            igSidebarLabel = uilabel(app.IG_SidebarPanel);
            igSidebarLabel.Position = [5 540 140 25];
            igSidebarLabel.Text = 'Images From Directory';
            igSidebarLabel.FontSize = 9;
            igSidebarLabel.FontWeight = 'bold';
            igSidebarLabel.HorizontalAlignment = 'center';
            igSidebarLabel.WordWrap = 'on';
            
            % Create 6 image buttons
            app.IG_ImageButtons = cell(6, 1);
            for i = 1:6
                app.IG_ImageButtons{i} = uibutton(app.IG_SidebarPanel, 'push');
                app.IG_ImageButtons{i}.Position = [10 480-(i-1)*60 130 45];
                app.IG_ImageButtons{i}.Text = sprintf('Image %d', i);
                app.IG_ImageButtons{i}.Enable = 'off';
                app.IG_ImageButtons{i}.BackgroundColor = [0.65 0.65 0.65];
                app.IG_ImageButtons{i}.FontSize = 9;
                app.IG_ImageButtons{i}.ButtonPushedFcn = @(btn,~) loadSidebarImage(app, btn, 'ImageGenerator');
            end
            
            % Parameters panel
            app.IG_ParametersPanel = uipanel(app.IGTab);
            app.IG_ParametersPanel.Title = 'Parametreler';
            app.IG_ParametersPanel.Position = [720 420 230 130];
            app.IG_ParametersPanel.FontWeight = 'bold';
            app.IG_ParametersPanel.BackgroundColor = [0.9 0.9 0.9];
            
            app.IG_StepsLabel = uilabel(app.IG_ParametersPanel);
            app.IG_StepsLabel.Position = [10 70 70 22];
            app.IG_StepsLabel.Text = 'Steps:';
            
            app.IG_StepsSpinner = uispinner(app.IG_ParametersPanel);
            app.IG_StepsSpinner.Position = [90 70 120 22];
            app.IG_StepsSpinner.Value = 25;
            app.IG_StepsSpinner.Limits = [10 50];
            app.IG_StepsSpinner.Step = 5;
            
            app.IG_GuidanceLabel = uilabel(app.IG_ParametersPanel);
            app.IG_GuidanceLabel.Position = [10 35 70 22];
            app.IG_GuidanceLabel.Text = 'Guidance:';
            
            app.IG_GuidanceSpinner = uispinner(app.IG_ParametersPanel);
            app.IG_GuidanceSpinner.Position = [90 35 120 22];
            app.IG_GuidanceSpinner.Value = 7.5;
            app.IG_GuidanceSpinner.Limits = [1 20];
            app.IG_GuidanceSpinner.Step = 0.5;
            
            % Main display area with placeholder
            app.IG_ImageAxes = uiaxes(app.IGTab);
            app.IG_ImageAxes.Position = [180 190 510 350];
            app.IG_ImageAxes.XTick = [];
            app.IG_ImageAxes.YTick = [];
            app.IG_ImageAxes.Box = 'on';
            app.IG_ImageAxes.Color = [0.75 0.75 0.75];
            
            app.IG_PlaceholderLabel = uilabel(app.IGTab);
            app.IG_PlaceholderLabel.Position = [180 190 510 350];
            app.IG_PlaceholderLabel.Text = {'Image Show'; 'Here'};
            app.IG_PlaceholderLabel.FontSize = 28;
            app.IG_PlaceholderLabel.FontWeight = 'bold';
            app.IG_PlaceholderLabel.FontColor = [0.4 0.4 0.4];
            app.IG_PlaceholderLabel.HorizontalAlignment = 'center';
            app.IG_PlaceholderLabel.VerticalAlignment = 'center';
            
            % Prompt section
            app.IG_PromptLabel = uilabel(app.IGTab);
            app.IG_PromptLabel.Position = [180 155 80 22];
            app.IG_PromptLabel.Text = 'Prompt';
            app.IG_PromptLabel.FontWeight = 'bold';
            
            app.IG_PromptTextArea = uitextarea(app.IGTab);
            app.IG_PromptTextArea.Position = [180 60 510 90];
            app.IG_PromptTextArea.Value = {''};
            
            % Buttons
            app.IG_GenerateButton = uibutton(app.IGTab, 'push');
            app.IG_GenerateButton.Position = [720 310 110 50];
            app.IG_GenerateButton.Text = 'Oluştur';
            app.IG_GenerateButton.FontSize = 12;
            app.IG_GenerateButton.FontWeight = 'bold';
            app.IG_GenerateButton.BackgroundColor = [0.65 0.65 0.65];
            app.IG_GenerateButton.ButtonPushedFcn = @(~,~) app.IG_Generate();
            
            app.IG_SaveButton = uibutton(app.IGTab, 'push');
            app.IG_SaveButton.Position = [840 310 110 50];
            app.IG_SaveButton.Text = 'Kaydet';
            app.IG_SaveButton.FontSize = 12;
            app.IG_SaveButton.FontWeight = 'bold';
            app.IG_SaveButton.BackgroundColor = [0.65 0.65 0.65];
            app.IG_SaveButton.Enable = 'off';
            app.IG_SaveButton.ButtonPushedFcn = @(~,~) app.IG_Save();
            
            app.IG_ClearButton = uibutton(app.IGTab, 'push');
            app.IG_ClearButton.Position = [720 240 230 50];
            app.IG_ClearButton.Text = 'Temizle';
            app.IG_ClearButton.FontSize = 12;
            app.IG_ClearButton.FontWeight = 'bold';
            app.IG_ClearButton.BackgroundColor = [0.65 0.65 0.65];
            app.IG_ClearButton.ButtonPushedFcn = @(~,~) app.IG_Clear();
            
            % Progress section
            app.IG_ProgressLabel = uilabel(app.IGTab);
            app.IG_ProgressLabel.Position = [180 30 120 22];
            app.IG_ProgressLabel.Text = 'Progress Bar';
            app.IG_ProgressLabel.FontWeight = 'bold';
            
            app.IG_ProgressGauge = uigauge(app.IGTab, 'linear');
            app.IG_ProgressGauge.Position = [180 10 510 20];
            app.IG_ProgressGauge.Limits = [0 100];
            app.IG_ProgressGauge.Value = 0;
            
            % Make figure visible
            app.UIFigure.Visible = 'on';
        end
    end
    
    methods (Access = public)
        
        function app = ImageProcessingApp
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            
            if nargout == 0
                clear app
            end
        end
        
        function delete(app)
            % Clean up
            if ~isempty(app.RT_Camera)
                app.RT_IsRunning = false;
                clear app.RT_Camera;
            end
            
            delete(app.UIFigure)
        end
    end
end

