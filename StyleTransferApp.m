classdef StyleTransferApp < handle
    % StyleTransferApp - Van Gogh's Starry Night Style Transfer UI
    % Save as: StyleTransferApp.m
    % Run with: app = StyleTransferApp();

    properties
        Figure
        LoadImageButton
        ApplyButton
        SaveButton
        AxStyleRef
        AxInput
        AxOutput
        Model
        OriginalImage
        StylizedImage
        ModelLoaded = false
    end

    methods
        function app = StyleTransferApp()
            app.createUI();
            drawnow;

            % Load model automatically if present
            if isfile('starry-night-styler.mat')
                try
                    s = load('starry-night-styler.mat');

                    if isfield(s, 'netTransform')
                        app.Model = s.netTransform;
                    else
                        fn = fieldnames(s);
                        for k = 1:numel(fn)
                            if isa(s.(fn{k}), 'dlnetwork')
                                app.Model = s.(fn{k});
                                break;
                            end
                        end
                    end

                    if ~isempty(app.Model)
                        app.ModelLoaded = true;
                    end
                catch ME
                    warning(ME.message);
                end
            end
        end

        function createUI(app)
            app.Figure = uifigure('Name', 'Van Gogh Style Transfer', ...
                'Position', [100 100 1000 600], ...
                'Color', [0.95 0.95 0.95]);

            % Title
            titleLabel = uilabel(app.Figure, ...
                'Text', 'Van Gogh''s Starry Night Styler', ...
                'Position', [20 550 960 40], ...
                'FontSize', 28, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');

            % Style reference preview (starryNight.jpg)
            app.AxStyleRef = uiaxes(app.Figure, 'Position', [70 250 250 250]);
            axis(app.AxStyleRef, 'off');
            title(app.AxStyleRef, 'Target Style', 'FontSize', 14, 'FontWeight', 'bold');
            
            % Load and display style reference if available
            if isfile('starryNight.jpg')
                styleImg = imread('starryNight.jpg');
                imshow(styleImg, 'Parent', app.AxStyleRef);
            else
                % Show placeholder
                text(app.AxStyleRef, 0.5, 0.5, 'starryNight.jpg', ...
                    'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', ...
                    'FontSize', 12);
            end

            % Content Image panel
            app.AxInput = uiaxes(app.Figure, 'Position', [375 250 250 250]);
            axis(app.AxInput, 'off');
            title(app.AxInput, 'Content Image', 'FontSize', 14, 'FontWeight', 'bold');
            text(app.AxInput, 0.5, 0.5, 'Content Image', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'FontSize', 16, ...
                'FontWeight', 'bold');

            % Stylized Image panel
            app.AxOutput = uiaxes(app.Figure, 'Position', [680 250 250 250]);
            axis(app.AxOutput, 'off');
            title(app.AxOutput, 'Stylized Image', 'FontSize', 14, 'FontWeight', 'bold');
            text(app.AxOutput, 0.5, 0.5, 'Stylized Image', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'FontSize', 16, ...
                'FontWeight', 'bold');

            % Buttons
            buttonY = 150;
            buttonWidth = 140;
            buttonHeight = 50;
            spacing = 50;
            
            totalWidth = 3*buttonWidth + 2*spacing;
            startX = (1000 - totalWidth)/2;

            app.LoadImageButton = uibutton(app.Figure, 'push', ...
                'Text', 'Load Image', ...
                'Position', [startX buttonY buttonWidth buttonHeight], ...
                'FontSize', 14, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.7 0.7 0.7], ...
                'ButtonPushedFcn', @(src,event)app.onLoadImage());

            app.ApplyButton = uibutton(app.Figure, 'push', ...
                'Text', 'Apply Style', ...
                'Position', [startX+buttonWidth+spacing buttonY buttonWidth buttonHeight], ...
                'FontSize', 14, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.7 0.7 0.7], ...
                'ButtonPushedFcn', @(src,event)app.onApplyStyle());

            app.SaveButton = uibutton(app.Figure, 'push', ...
                'Text', 'Save Result', ...
                'Position', [startX+2*(buttonWidth+spacing) buttonY buttonWidth buttonHeight], ...
                'FontSize', 14, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.7 0.7 0.7], ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(src,event)app.onSave());
        end

        function onLoadImage(app)
            [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp'}, 'Select image');
            if isequal(file,0), return; end

            img = imread(fullfile(path, file));
            app.OriginalImage = img;

            cla(app.AxInput);
            imshow(img, 'Parent', app.AxInput);
            title(app.AxInput, 'Content Image', 'FontSize', 14, 'FontWeight', 'bold');
        end

        function onApplyStyle(app)
            if isempty(app.OriginalImage)
                uialert(app.Figure, 'Please load an image first.', 'No Image');
                return;
            end
            if ~app.ModelLoaded
                uialert(app.Figure, 'Model not loaded. Please ensure starry-night-styler.mat is in the working folder.', 'Error');
                return;
            end

            img = app.OriginalImage;

            if size(img,3)==1
                img = repmat(img,1,1,3);
            end

            imgResized = imresize(img, [256 256]);
            imgSingle = single(imgResized);

            % Correct input: SSCB (spatial, spatial, channel, batch)
            dlImg = dlarray(imgSingle, 'SSCB');

            useGPU = canUseGPU();
            if useGPU
                dlImg = gpuArray(dlImg);
            end

            pd = uiprogressdlg(app.Figure, ...
                'Title', 'Applying Style', ...
                'Message', 'Preparing...', ...
                'Indeterminate', 'off', ...
                'Cancelable', 'off');

            try
                pd.Value = 0.2;
                pd.Message = 'Running network...';
                drawnow;

                % Forward pass
                stylized = predict(app.Model, dlImg);

                pd.Value = 0.8;
                pd.Message = 'Post-processing...';
                drawnow;

                % Correct output scaling: tanh -> [-1,1] -> [0,255]
                stylized = 255*(tanh(stylized)+1)/2;
                stylized = uint8(gather(extractdata(stylized)));

                app.StylizedImage = stylized;
                cla(app.AxOutput);
                imshow(stylized, 'Parent', app.AxOutput);
                title(app.AxOutput, 'Stylized Image', 'FontSize', 14, 'FontWeight', 'bold');
                app.SaveButton.Enable = 'on';

                pd.Value = 1;
                pd.Message = 'Done';
                pause(0.2);
                close(pd);

            catch ME
                close(pd);
                errordlg(['Error during inference: ' ME.message]);
            end
        end

        function onSave(app)
            if isempty(app.StylizedImage)
                return;
            end

            [file, path] = uiputfile({'*.png'; '*.jpg'}, 'Save stylized image');
            if isequal(file,0), return; end

            imwrite(app.StylizedImage, fullfile(path, file));
            uialert(app.Figure, 'Image saved successfully!', 'Success');
        end
    end
end