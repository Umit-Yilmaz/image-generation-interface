classdef upsampleLayer < nnet.layer.Layer
    
    methods
        function layer = upsampleLayer(args)

            arguments
                args.Name = "";
            end
            
            layer.Name = args.Name;

            layer.Type = "Upsample";
            layer.Description = "Upsample";
            
        end
        
        function Z = predict(~, X)
            
            [h, w, c, n] = size(X,1:4);
            
            Z = zeros([2*h 2*w c n],"like",X);
            
            Z(1:2:end,1:2:end,:,:) = X;
            Z(1:2:end,2:2:end,:,:) = X;
            Z(2:2:end,1:2:end,:,:) = X;
            Z(2:2:end,2:2:end,:,:) = X;
        end
    end   
end